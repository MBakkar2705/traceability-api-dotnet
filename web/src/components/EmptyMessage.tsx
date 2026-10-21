import type { ReactNode } from 'react'

export default function EmptyMessage({ children }: { children: ReactNode }) {
  return <p className="py-8 text-center text-ink-soft">{children}</p>
}
