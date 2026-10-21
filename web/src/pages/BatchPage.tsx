import { useCallback } from 'react'
import { Link, useParams } from 'react-router'
import { getBatch } from '../api/client'
import type { Movement } from '../api/types'
import BackLink from '../components/BackLink'
import type { Column } from '../components/column'
import DataTable from '../components/DataTable'
import DetailCard from '../components/DetailCard'
import ErrorMessage from '../components/ErrorMessage'
import ListCard from '../components/ListCard'
import Loading from '../components/Loading'
import PageTitle from '../components/PageTitle'
import StatusBadge from '../components/StatusBadge'
import { formatDate, formatKg, formatUtc } from '../lib/format'
import { movementLabel } from '../lib/labels'
import { useApi } from '../lib/useApi'

const MOVEMENT_COLUMNS: Column<Movement>[] = [
  { header: 'Étape', cell: (movement) => movementLabel(movement.movementType) },
  {
    header: 'Station',
    cell: (movement) => (
      <Link to={`/stations/${encodeURIComponent(movement.stationCode)}`} className="text-link underline">
        {movement.stationCode}
      </Link>
    ),
    mono: true,
  },
  { header: 'Quantité', cell: (movement) => formatKg(movement.quantityKg), right: true },
  { header: 'Date et heure', cell: (movement) => formatUtc(movement.occurredAt) },
]

export default function BatchPage() {
  const { batchCode = '' } = useParams()

  const load = useCallback((signal: AbortSignal) => getBatch(batchCode, signal), [batchCode])
  const state = useApi(load)

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
        </>
      )}
    </section>
  )
}
