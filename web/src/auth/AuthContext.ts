import { createContext, useContext } from 'react'

// Why nobody is signed in, when it is worth saying.
export type SignedOutReason = 'expired' | 'unreachable'

export type AuthState =
  | { status: 'loading' }
  | { status: 'signedOut'; reason?: SignedOutReason }
  | { status: 'signedIn'; userName: string; roles: string[] }

export interface Auth {
  state: AuthState
  signIn: () => void
  signOut: () => void
}

// Without a provider nobody is signed in, so what writes stays hidden: a missing provider never
// shows more.
export const AuthContext = createContext<Auth>({
  state: { status: 'signedOut' },
  signIn: () => undefined,
  signOut: () => undefined,
})

export function useAuth(): Auth {
  return useContext(AuthContext)
}
