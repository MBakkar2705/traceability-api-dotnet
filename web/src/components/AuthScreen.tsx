import type { ReactNode } from 'react'

// A bare screen for what comes before the application: the sign-in and its return from Keycloak.
export default function AuthScreen({ children }: { children: ReactNode }) {
  return (
    <div className="min-h-screen bg-page text-base text-ink">
      <main className="mx-auto max-w-md px-4 py-10">{children}</main>
    </div>
  )
}
