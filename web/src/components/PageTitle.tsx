import type { ReactNode } from 'react'

// The title of a page, on a small background so that it stays readable over the wallpaper.
export default function PageTitle({ children }: { children: ReactNode }) {
  return <h1 className="mb-3 inline-block rounded bg-veil px-3 py-1 text-2xl font-semibold">{children}</h1>
}
