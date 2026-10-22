import { useCallback } from 'react'
import type { FormEvent } from 'react'
import { Link, useSearchParams } from 'react-router'
import { listBatches } from '../api/client'
import { BATCH_STATUSES } from '../api/types'
import type { Batch } from '../api/types'
import type { Column } from '../components/column'
import ListView from '../components/ListView'
import PageTitle from '../components/PageTitle'
import StatusBadge from '../components/StatusBadge'
import { BUTTON, FIELD } from '../components/styles'
import { PAGE_SIZE } from '../config'
import { formatDate, formatKg } from '../lib/format'
import { statusLabel } from '../lib/labels'
import { readPageNumber } from '../lib/page'
import { useApi } from '../lib/useApi'

const COLUMNS: Column<Batch>[] = [
  {
    header: 'Code',
    cell: (batch) => (
      <Link to={`/batches/${encodeURIComponent(batch.batchCode)}`} className="text-link underline">
        {batch.batchCode}
      </Link>
    ),
    mono: true,
  },
  { header: 'Ferme', cell: (batch) => batch.farmCode, mono: true, secondary: true },
  { header: 'Variété', cell: (batch) => batch.variety, secondary: true },
  { header: 'Récolte', cell: (batch) => formatDate(batch.harvestDate) },
  { header: 'Quantité', cell: (batch) => formatKg(batch.quantityKg), right: true },
  { header: 'Statut', cell: (batch) => <StatusBadge status={batch.status} /> },
]

// The filters and the page are kept in the address: ?status=SHIPPED&farmCode=F001&page=2
export default function BatchesPage() {
  const [searchParams, setSearchParams] = useSearchParams()
  const pageNumber = readPageNumber(searchParams.get('page'))
  const status = searchParams.get('status') ?? ''
  const farmCode = searchParams.get('farmCode') ?? ''
  const filtered = status !== '' || farmCode !== ''

  const load = useCallback(
    (signal: AbortSignal) => listBatches({ status, farmCode, pageNumber, pageSize: PAGE_SIZE }, signal),
    [status, farmCode, pageNumber],
  )
  const state = useApi(load)

  // Applying the filters goes back to page 1.
  function applyFilters(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const data = new FormData(event.currentTarget)
    const next = new URLSearchParams()
    const newStatus = String(data.get('status') ?? '')
    const newFarmCode = String(data.get('farmCode') ?? '').trim()
    if (newStatus) {
      next.set('status', newStatus)
    }
    if (newFarmCode) {
      next.set('farmCode', newFarmCode)
    }
    setSearchParams(next)
  }

  function changePage(page: number) {
    const next = new URLSearchParams(searchParams)
    next.set('page', String(page))
    setSearchParams(next)
  }

  return (
    <section>
      {/* The title and the filters share a line (they go under each other on a narrow screen). */}
      <div className="flex flex-wrap items-start gap-x-3">
        <PageTitle>Lots</PageTitle>
        <Link to="/new-batch" className={`${BUTTON} mb-3 inline-block`}>
          Nouveau lot
        </Link>

        {/* The key makes the form start again from the address when the address changes. */}
        <form
          key={searchParams.toString()}
          onSubmit={applyFilters}
          className="mb-3 flex flex-wrap items-end gap-3 rounded border border-edge-strong bg-paper p-3 shadow-sm"
        >
          <label className="flex flex-col gap-1">
            <span className="text-sm text-ink-soft">Statut</span>
            <select name="status" defaultValue={status} className={FIELD}>
              <option value="">Tous</option>
              {BATCH_STATUSES.map((value) => (
                <option key={value} value={value}>
                  {statusLabel(value)}
                </option>
              ))}
            </select>
          </label>
          <label className="flex flex-col gap-1">
            <span className="text-sm text-ink-soft">Ferme</span>
            <input name="farmCode" defaultValue={farmCode} placeholder="F001" className={`${FIELD} w-32`} />
          </label>
          <button type="submit" className={BUTTON}>
            Filtrer
          </button>
          {filtered && (
            <button type="button" className={BUTTON} onClick={() => setSearchParams({})}>
              Effacer les filtres
            </button>
          )}
        </form>
      </div>

      <ListView
        state={state}
        columns={COLUMNS}
        rowKey={(batch) => batch.batchCode}
        emptyText={filtered ? 'Aucun lot ne correspond à ces filtres.' : 'Aucun lot enregistré.'}
        pageNumber={pageNumber}
        pageSize={PAGE_SIZE}
        onPageChange={changePage}
        loadingHint="La liste des lots peut prendre quelques secondes."
      />
    </section>
  )
}
