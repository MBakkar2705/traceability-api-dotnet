import { useCallback, useState } from 'react'
import type { ReactNode } from 'react'
import { Link, Navigate, useNavigate, useParams } from 'react-router'
import { getBatch } from '../api/client'
import type { Correction, Movement, SheetCorrection } from '../api/types'
import AddMovementForm from '../components/AddMovementForm'
import BackLink from '../components/BackLink'
import type { Column } from '../components/column'
import CorrectionForm from '../components/CorrectionForm'
import DataTable from '../components/DataTable'
import DetailCard from '../components/DetailCard'
import ErrorMessage from '../components/ErrorMessage'
import ListCard from '../components/ListCard'
import Loading from '../components/Loading'
import PageTitle from '../components/PageTitle'
import RecipientMessage from '../components/RecipientMessage'
import SheetCorrectionForm from '../components/SheetCorrectionForm'
import StatusBadge from '../components/StatusBadge'
import SuccessMessage from '../components/SuccessMessage'
import SupervisorOnly from '../components/SupervisorOnly'
import WriterOnly from '../components/WriterOnly'
import { formatDate, formatKg, formatUtc } from '../lib/format'
import { authorLabel, correctionKindLabel, movementLabel, reasonLabel } from '../lib/labels'
import { recipientMessage, sheetRecipientMessage } from '../lib/recipientMessage'
import type { CorrectionSummary, SheetCorrectionSummary } from '../lib/recipientMessage'
import { sheetChanges } from '../lib/sheetChanges'
import { useApi } from '../lib/useApi'

// A cancelled movement did not happen: its values stay readable, struck through.
function struck(movement: Movement, content: ReactNode): ReactNode {
  return movement.isCancelled ? <span className="text-ink-soft line-through">{content}</span> : content
}

// The value first entered, shown under the valid value when a correction changed it.
function Original({ children }: { children: ReactNode }) {
  return <span className="block text-xs font-normal text-ink-soft">{children}</span>
}

// Lot 12b: the API sends the names of the authors (authorName) to the auditor and to the supervisor
// only; the others get null. The columns of the authors are then left out of the tables.
const AUTHOR_HEADERS = ['Auteur', 'Corrigé par']

function hasAuthors(items: Array<{ authorName: string | null }>): boolean {
  return items.some((item) => item.authorName !== null)
}

function withoutAuthors<T>(columns: Column<T>[], show: boolean): Column<T>[] {
  return show ? columns : columns.filter((column) => !AUTHOR_HEADERS.includes(column.header))
}

const MOVEMENT_COLUMNS: Column<Movement>[] = [
  { header: 'Étape', cell: (movement) => struck(movement, movementLabel(movement.movementType)) },
  {
    header: 'Station',
    cell: (movement) =>
      struck(
        movement,
        <>
          <Link to={`/stations/${encodeURIComponent(movement.stationCode)}`} className="text-link underline">
            {movement.stationCode}
          </Link>
          {movement.stationCode !== movement.originalStationCode && (
            <Original>{`saisie : ${movement.originalStationCode}`}</Original>
          )}
        </>,
      ),
    mono: true,
  },
  {
    header: 'Quantité',
    cell: (movement) =>
      struck(
        movement,
        <>
          {formatKg(movement.quantityKg)}
          {movement.quantityKg !== movement.originalQuantityKg && (
            <Original>{`saisie : ${formatKg(movement.originalQuantityKg)}`}</Original>
          )}
        </>,
      ),
    right: true,
  },
  {
    header: 'Date et heure',
    cell: (movement) =>
      struck(
        movement,
        <>
          {formatUtc(movement.occurredAt)}
          {formatUtc(movement.occurredAt) !== formatUtc(movement.originalOccurredAt) && (
            <Original>{`saisie : ${formatUtc(movement.originalOccurredAt)}`}</Original>
          )}
        </>,
      ),
  },
  { header: 'Auteur', cell: (movement) => authorLabel(movement.authorName) },
  {
    header: 'État',
    cell: (movement) => {
      if (movement.isCancelled) {
        return <span className="rounded-full bg-red-100 px-2.5 py-0.5 text-sm font-medium text-red-900">Annulé</span>
      }
      return movement.correctionCount > 0 ? (
        <span className="rounded-full bg-amber-100 px-2.5 py-0.5 text-sm font-medium text-amber-900">Corrigé</span>
      ) : null
    },
  },
]

// The reason of a correction, with its comment under it.
function Reason({ code, comment }: { code: string; comment: string }) {
  return (
    <>
      {reasonLabel(code)}
      {comment !== '' && <span className="block text-sm text-ink-soft">{comment}</span>}
    </>
  )
}

// The history of the corrections of the movements (lot 12a), in the order they were made. The name
// of the author is shown only when the API sends it (lot 12b).
const CORRECTION_COLUMNS: Column<Correction>[] = [
  { header: 'Date de la correction', cell: (correction) => formatUtc(correction.correctedAt) },
  { header: 'Mouvement', cell: (correction) => movementLabel(correction.movementType) },
  { header: 'Correction', cell: (correction) => correctionKindLabel(correction.kind) },
  {
    header: 'Nouvelles valeurs',
    cell: (correction) =>
      correction.kind === 'CANCEL'
        ? '—'
        : `${correction.stationCode} · ${formatKg(correction.quantityKg)} · ${formatUtc(correction.occurredAt)}`,
  },
  { header: 'Motif', cell: (correction) => <Reason code={correction.reasonCode} comment={correction.reasonComment} /> },
  { header: 'Corrigé par', cell: (correction) => authorLabel(correction.authorName) },
]

// The history of the corrections of the sheet (lot 12b): only the fields that changed are listed.
const SHEET_CORRECTION_COLUMNS: Column<SheetCorrection>[] = [
  { header: 'Date de la correction', cell: (correction) => formatUtc(correction.correctedAt) },
  {
    header: 'Modifications',
    cell: (correction) =>
      sheetChanges(
        {
          batchCode: correction.oldBatchCode,
          farmCode: correction.oldFarmCode,
          variety: correction.oldVariety,
          harvestDate: correction.oldHarvestDate,
        },
        {
          batchCode: correction.newBatchCode,
          farmCode: correction.newFarmCode,
          variety: correction.newVariety,
          harvestDate: correction.newHarvestDate,
        },
      ).map((line) => (
        <span key={line} className="block">
          {line}
        </span>
      )),
  },
  { header: 'Motif', cell: (correction) => <Reason code={correction.reasonCode} comment={correction.reasonComment} /> },
  { header: 'Corrigé par', cell: (correction) => authorLabel(correction.authorName) },
]

export default function BatchPage() {
  const { batchCode = '' } = useParams()
  const navigate = useNavigate()
  // Raised when a movement has been added: the batch is read again.
  const [refresh, setRefresh] = useState(0)
  // The last movement added, with the batch it was added to (the message is only for that batch).
  const [added, setAdded] = useState<{ batchCode: string; type: string } | null>(null)
  // The last correction (lot 12a), with the batch it was made on, and whether the batch was
  // SHIPPED when it was corrected: then the supervisor gets a message to forward to the recipient.
  const [corrected, setCorrected] = useState<{
    batchCode: string
    summary: CorrectionSummary
    shipped: boolean
  } | null>(null)

  // The last correction of the sheet (lot 12b). batchCode is the code the batch has AFTER the
  // correction, which is the code of the address once the page has moved to it.
  const [sheetCorrected, setSheetCorrected] = useState<{
    batchCode: string
    summary: SheetCorrectionSummary
    shipped: boolean
  } | null>(null)

  const load = useCallback((signal: AbortSignal) => getBatch(batchCode, signal), [batchCode])
  const state = useApi(load, refresh)

  // An old code of the batch reads the batch (the API finds it) but cannot write (error 50104). The
  // address is replaced by the current code, so that every form writes with the current code. While
  // the address changes, `useApi` never shows the old answer, so this cannot loop.
  if (state.status === 'success' && state.data.batchCode !== batchCode) {
    return <Navigate to={`/batches/${encodeURIComponent(state.data.batchCode)}`} replace />
  }

  return (
    <section>
      <BackLink to="/batches">Retour aux lots</BackLink>
      <PageTitle>Lot {batchCode}</PageTitle>

      {state.status === 'loading' && <Loading />}
      {state.status === 'error' && <ErrorMessage error={state.error} />}
      {state.status === 'success' && (
        <>
          <DetailCard
            fields={[
              { label: 'Code', value: <span className="font-mono">{state.data.batchCode}</span> },
              { label: 'Ferme', value: <span className="font-mono">{state.data.farmCode}</span> },
              { label: 'Variété', value: state.data.variety },
              { label: 'Récolte', value: formatDate(state.data.harvestDate) },
              { label: 'Quantité', value: formatKg(state.data.quantityKg) },
              { label: 'Statut', value: <StatusBadge status={state.data.status} /> },
            ]}
          />
          <h2 className="mt-5 mb-2 inline-block rounded bg-veil px-3 py-1 text-lg font-semibold">Parcours</h2>
          <div>
            <ListCard>
              {state.data.movements.length === 0 ? (
                <p className="py-8 text-center text-ink-soft">Aucun mouvement enregistré.</p>
              ) : (
                <DataTable
                  columns={withoutAuthors(MOVEMENT_COLUMNS, hasAuthors(state.data.movements))}
                  items={state.data.movements}
                  rowKey={(movement) => String(movement.movementId)}
                />
              )}
            </ListCard>
          </div>

          {state.data.corrections.length > 0 && (
            <>
              <h2 className="mt-5 mb-2 inline-block rounded bg-veil px-3 py-1 text-lg font-semibold">Corrections</h2>
              <div>
                <ListCard>
                  <DataTable
                    columns={withoutAuthors(CORRECTION_COLUMNS, hasAuthors(state.data.corrections))}
                    items={state.data.corrections}
                    rowKey={(correction) => String(correction.correctionId)}
                  />
                </ListCard>
              </div>
            </>
          )}

          {state.data.sheetCorrections.length > 0 && (
            <>
              <h2 className="mt-5 mb-2 inline-block rounded bg-veil px-3 py-1 text-lg font-semibold">
                Corrections de la fiche
              </h2>
              <div>
                <ListCard>
                  <DataTable
                    columns={withoutAuthors(SHEET_CORRECTION_COLUMNS, hasAuthors(state.data.sheetCorrections))}
                    items={state.data.sheetCorrections}
                    rowKey={(correction) => String(correction.correctionId)}
                  />
                </ListCard>
              </div>
            </>
          )}

          <WriterOnly>
            <h2 className="mt-5 mb-2 inline-block rounded bg-veil px-3 py-1 text-lg font-semibold">Ajouter un mouvement</h2>
            {added?.batchCode === batchCode && (
              <div className="mb-3">
                <SuccessMessage>{`Mouvement ${movementLabel(added.type)} ajouté.`}</SuccessMessage>
              </div>
            )}
            {state.data.status === 'SHIPPED' ? (
              <p className="rounded bg-veil p-3">Ce lot est expédié : aucun mouvement n'est plus possible.</p>
            ) : (
              <AddMovementForm
                key={state.data.status}
                batchCode={batchCode}
                status={state.data.status}
                quantityKg={state.data.quantityKg}
                onStart={() => setAdded(null)}
                onAdded={(type) => {
                  setAdded({ batchCode, type })
                  setRefresh((n) => n + 1)
                }}
              />
            )}
          </WriterOnly>

          <SupervisorOnly>
            <h2 className="mt-5 mb-2 inline-block rounded bg-veil px-3 py-1 text-lg font-semibold">Corriger un mouvement</h2>
            {corrected?.batchCode === batchCode && (
              <div className="mb-3">
                <SuccessMessage>
                  {corrected.summary.kind === 'CANCEL' ? 'Mouvement annulé.' : 'Correction enregistrée.'}
                </SuccessMessage>
                {corrected.shipped && <RecipientMessage message={recipientMessage(corrected.summary)} />}
              </div>
            )}
            <CorrectionForm
              key={`${state.data.movements.length}-${state.data.corrections.length}`}
              batchCode={batchCode}
              movements={state.data.movements}
              onStart={() => setCorrected(null)}
              onCorrected={(summary) => {
                setCorrected({
                  batchCode,
                  summary,
                  shipped: state.data.status === 'SHIPPED',
                })
                setRefresh((n) => n + 1)
              }}
            />

            <h2 className="mt-5 mb-2 inline-block rounded bg-veil px-3 py-1 text-lg font-semibold">Corriger la fiche</h2>
            {sheetCorrected?.batchCode === batchCode && (
              <div className="mb-3">
                <SuccessMessage>Fiche corrigée.</SuccessMessage>
                {sheetCorrected.shipped && (
                  <RecipientMessage message={sheetRecipientMessage(sheetCorrected.summary)} />
                )}
              </div>
            )}
            <SheetCorrectionForm
              key={`${state.data.batchCode}-${state.data.sheetCorrections.length}`}
              batchCode={batchCode}
              sheet={{
                batchCode: state.data.batchCode,
                farmCode: state.data.farmCode,
                variety: state.data.variety,
                harvestDate: state.data.harvestDate,
              }}
              onStart={() => setSheetCorrected(null)}
              onCorrected={(summary) => {
                setSheetCorrected({
                  batchCode: summary.after.batchCode,
                  summary,
                  shipped: state.data.status === 'SHIPPED',
                })
                if (summary.after.batchCode === batchCode) {
                  setRefresh((n) => n + 1)
                } else {
                  navigate(`/batches/${encodeURIComponent(summary.after.batchCode)}`, { replace: true })
                }
              }}
            />
          </SupervisorOnly>
        </>
      )}
    </section>
  )
}
