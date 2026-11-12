import { useCallback, useState } from 'react'
import type { ReactNode } from 'react'
import { Link, useParams } from 'react-router'
import { getBatch } from '../api/client'
import type { Correction, Movement } from '../api/types'
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
import StatusBadge from '../components/StatusBadge'
import SuccessMessage from '../components/SuccessMessage'
import SupervisorOnly from '../components/SupervisorOnly'
import WriterOnly from '../components/WriterOnly'
import { formatDate, formatKg, formatUtc } from '../lib/format'
import { authorLabel, correctionKindLabel, movementLabel, reasonLabel } from '../lib/labels'
import { recipientMessage } from '../lib/recipientMessage'
import type { CorrectionSummary } from '../lib/recipientMessage'
import { useApi } from '../lib/useApi'

// A cancelled movement did not happen: its values stay readable, struck through.
function struck(movement: Movement, content: ReactNode): ReactNode {
  return movement.isCancelled ? <span className="text-ink-soft line-through">{content}</span> : content
}

// The value first entered, shown under the valid value when a correction changed it.
function Original({ children }: { children: ReactNode }) {
  return <span className="block text-xs font-normal text-ink-soft">{children}</span>
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

// The history of the corrections (lot 12a), in the order they were made. The name of the author is
// shown to everyone who can read the batch.
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
  {
    header: 'Motif',
    cell: (correction) => (
      <>
        {reasonLabel(correction.reasonCode)}
        {correction.reasonComment !== '' && (
          <span className="block text-sm text-ink-soft">{correction.reasonComment}</span>
        )}
      </>
    ),
  },
  { header: 'Corrigé par', cell: (correction) => authorLabel(correction.authorName) },
]

export default function BatchPage() {
  const { batchCode = '' } = useParams()
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

  const load = useCallback((signal: AbortSignal) => getBatch(batchCode, signal), [batchCode])
  const state = useApi(load, refresh)

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
                  columns={MOVEMENT_COLUMNS}
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
                    columns={CORRECTION_COLUMNS}
                    items={state.data.corrections}
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
          </SupervisorOnly>
        </>
      )}
    </section>
  )
}
