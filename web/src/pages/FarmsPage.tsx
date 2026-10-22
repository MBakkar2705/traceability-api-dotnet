import { useCallback } from 'react'
import { Link, useSearchParams } from 'react-router'
import { listFarms } from '../api/client'
import type { Farm } from '../api/types'
import type { Column } from '../components/column'
import ListView from '../components/ListView'
import PageTitle from '../components/PageTitle'
import { BUTTON } from '../components/styles'
import { PAGE_SIZE } from '../config'
import { readPageNumber } from '../lib/page'
import { useApi } from '../lib/useApi'

const COLUMNS: Column<Farm>[] = [
  { header: 'Code', cell: (farm) => farm.code, mono: true },
  { header: 'Nom', cell: (farm) => farm.name },
  { header: 'Région', cell: (farm) => farm.region },
]

export default function FarmsPage() {
  const [searchParams, setSearchParams] = useSearchParams()
  const pageNumber = readPageNumber(searchParams.get('page'))

  const load = useCallback(
    (signal: AbortSignal) => listFarms({ pageNumber, pageSize: PAGE_SIZE }, signal),
    [pageNumber],
  )
  const state = useApi(load)

  return (
    <section>
      <div className="flex flex-wrap items-start gap-x-3">
        <PageTitle>Fermes</PageTitle>
        <Link to="/new-farm" className={`${BUTTON} mb-3 inline-block`}>
          Nouvelle ferme
        </Link>
      </div>
      <ListView
        state={state}
        columns={COLUMNS}
        rowKey={(farm) => farm.code}
        emptyText="Aucune ferme enregistrée."
        pageNumber={pageNumber}
        pageSize={PAGE_SIZE}
        onPageChange={(page) => setSearchParams({ page: String(page) })}
      />
    </section>
  )
}
