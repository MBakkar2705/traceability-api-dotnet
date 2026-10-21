import { BUTTON } from './styles'

interface PaginationProps {
  pageNumber: number
  pageSize: number
  totalCount: number
  onPageChange: (pageNumber: number) => void
}

export default function Pagination({ pageNumber, pageSize, totalCount, onPageChange }: PaginationProps) {
  const totalPages = Math.max(1, Math.ceil(totalCount / pageSize))
  const goTo = (page: number) => () => onPageChange(page)

  return (
    <nav
      aria-label="Pagination"
      className="flex flex-wrap items-center justify-between gap-3 border-t border-edge bg-paper-bar px-4 py-3"
    >
      <div className="flex gap-2">
        <button type="button" className={BUTTON} disabled={pageNumber <= 1} onClick={goTo(1)}>
          « Début
        </button>
        {/* Beyond the end, "previous" goes back to the real last page, not to the page just before. */}
        <button
          type="button"
          className={BUTTON}
          disabled={pageNumber <= 1}
          onClick={goTo(Math.min(pageNumber - 1, totalPages))}
        >
          ‹ Précédent
        </button>
      </div>
      <p className="px-2 font-medium text-ink-soft">
        Page {pageNumber.toLocaleString('fr-FR')} sur {totalPages.toLocaleString('fr-FR')} ·{' '}
        {totalCount.toLocaleString('fr-FR')} au total
      </p>
      <div className="flex gap-2">
        <button type="button" className={BUTTON} disabled={pageNumber >= totalPages} onClick={goTo(pageNumber + 1)}>
          Suivant ›
        </button>
        <button type="button" className={BUTTON} disabled={pageNumber >= totalPages} onClick={goTo(totalPages)}>
          Fin »
        </button>
      </div>
    </nav>
  )
}
