import type { ReactNode } from 'react'

// The message that says a write worked (for example "Ferme F001 créée.").
export default function SuccessMessage({ children }: { children: ReactNode }) {
  return (
    <div role="status" className="rounded border border-green-200 bg-green-50 p-4 text-green-900">
      {children}
    </div>
  )
}
