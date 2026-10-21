import { useCallback } from 'react'
import { Link, useSearchParams } from 'react-router'
import { listStations } from '../api/client'
import type { Station } from '../api/types'
import type { Column } from '../components/column'
import ListView from '../components/ListView'
import PageTitle from '../components/PageTitle'
import { PAGE_SIZE } from '../config'
import { readPageNumber } from '../lib/page'
import { useApi } from '../lib/useApi'

const COLUMNS: Column<Station>[] = [
  {
    header: 'Code',
    cell: (station) => (
      <Link to={`/stations/${encodeURIComponent(station.code)}`} className="text-link underline">
        {station.code}
      </Link>
    ),
    mono: true,
  },
  { header: 'Nom', cell: (station) => station.name },
]

export default function StationsPage() {
  const [searchParams, setSearchParams] = useSearchParams()
  const pageNumber = readPageNumber(searchParams.get('page'))

  const load = useCallback(
    (signal: AbortSignal) => listStations({ pageNumber, pageSize: PAGE_SIZE }, signal),
    [pageNumber],
  )
  const state = useApi(load)

  return (
    <section>
      <PageTitle>Stations</PageTitle>
      <ListView
        state={state}
        columns={COLUMNS}
        rowKey={(station) => station.code}
        emptyText="Aucune station enregistrée."
        pageNumber={pageNumber}
        pageSize={PAGE_SIZE}
        onPageChange={(page) => setSearchParams({ page: String(page) })}
      />
    </section>
  )
}
