import type { ReactNode } from 'react'
import { Link } from 'react-router'

export default function BackLink({ to, children }: { to: string; children: ReactNode }) {
  return (
    <Link to={to} className="mb-3 mr-3 inline-block rounded bg-veil px-3 py-1 text-link underline">
      ‹ {children}
    </Link>
  )
}
