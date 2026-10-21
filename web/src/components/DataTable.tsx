import type { Column } from './column'

// The classes of a cell (header or data) for a column: tight on a small screen, roomy from 640px.
function cellClass<T>(column: Column<T>, base: string): string {
  return [
    base,
    column.mono ? 'font-mono whitespace-nowrap' : '',
    column.right ? 'text-right' : '',
    column.secondary ? 'hidden sm:table-cell' : '',
  ]
    .filter(Boolean)
    .join(' ')
}

export default function DataTable<T>({
  columns,
  items,
  rowKey,
}: {
  columns: Column<T>[]
  items: T[]
  rowKey: (item: T) => string
}) {
  return (
    <table className="w-full border-collapse text-left text-sm sm:text-base">
      <thead>
        <tr className="bg-paper-head text-ink-soft">
          {columns.map((column) => (
            <th key={column.header} className={cellClass(column, 'px-3 py-2 font-semibold sm:px-6')}>
              {column.header}
            </th>
          ))}
        </tr>
      </thead>
      <tbody>
        {items.map((item) => (
          <tr key={rowKey(item)} className="border-t border-edge hover:bg-paper-hover">
            {columns.map((column) => (
              <td key={column.header} className={cellClass(column, 'px-3 py-1.5 sm:px-6')}>
                {column.cell(item)}
              </td>
            ))}
          </tr>
        ))}
      </tbody>
    </table>
  )
}
