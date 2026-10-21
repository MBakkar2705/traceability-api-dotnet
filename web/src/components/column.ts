import type { ReactNode } from 'react'

// A column of a table: its header, what to show in a cell for an item, and a few style choices.
//   mono      a code: fixed-width font, kept on one line.
//   right     numbers: aligned to the right.
//   secondary less important: not shown on a small screen (under 640px), to avoid scrolling sideways.
export interface Column<T> {
  header: string
  cell: (item: T) => ReactNode
  mono?: boolean
  right?: boolean
  secondary?: boolean
}
