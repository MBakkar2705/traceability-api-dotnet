import type { Page } from '../api/types'
import type { ApiState } from '../lib/useApi'
import type { Column } from './column'
import DataTable from './DataTable'
import EmptyMessage from './EmptyMessage'
import ErrorMessage from './ErrorMessage'
import ListCard from './ListCard'
import Loading from './Loading'
import Pagination from './Pagination'

interface ListViewProps<T> {
  state: ApiState<Page<T>>
  columns: Column<T>[]
  rowKey: (item: T) => string
  // Shown when there is nothing at all (not when the page asked is simply beyond the end).
  emptyText: string
  pageNumber: number
  pageSize: number
  onPageChange: (pageNumber: number) => void
  loadingHint?: string
}

// What a list screen shows for each state of its call: loading, error, or the table with its pagination.
export default function ListView<T>({
  state,
  columns,
  rowKey,
  emptyText,
  pageNumber,
  pageSize,
  onPageChange,
  loadingHint,
}: ListViewProps<T>) {
  if (state.status === 'loading') {
    return <Loading hint={loadingHint} />
  }
  if (state.status === 'error') {
    return <ErrorMessage error={state.error} />
  }

  const { items, totalCount } = state.data
  return (
    <ListCard>
      {items.length === 0 ? (
        <EmptyMessage>{totalCount === 0 ? emptyText : 'Cette page est vide.'}</EmptyMessage>
      ) : (
        <DataTable columns={columns} items={items} rowKey={rowKey} />
      )}
      <Pagination pageNumber={pageNumber} pageSize={pageSize} totalCount={totalCount} onPageChange={onPageChange} />
    </ListCard>
  )
}
