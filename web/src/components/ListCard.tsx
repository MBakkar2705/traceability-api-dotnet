import type { ReactNode } from 'react'

// The table and its pagination in one box: as wide as its content, at least 44rem on a medium or
// large screen, and never wider than the screen.
export default function ListCard({ children }: { children: ReactNode }) {
  return (
    <div className="w-fit max-w-full overflow-x-auto rounded border border-edge-strong bg-paper shadow-sm md:min-w-[44rem]">
      {children}
    </div>
  )
}
