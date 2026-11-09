import { render } from '@testing-library/react'
import { MemoryRouter } from 'react-router'
import { vi } from 'vitest'
import App from '../App'
import { AuthContext } from '../auth/AuthContext'
import type { AuthState } from '../auth/AuthContext'

// Who is signed in, for the tests (lot 10c). The real sign-in with Keycloak is not played here.
export const WRITER: AuthState = { status: 'signedIn', userName: 'writer-test', roles: ['writer'] }
export const READER: AuthState = { status: 'signedIn', userName: 'reader-test', roles: ['reader'] }

// The whole application, as if the browser were at this address. By default a writer is signed
// in, so that the screens show everything they offer. It gives back the result of render and the
// two spies behind the sign-in and sign-out buttons.
export function renderApp(url: string, state: AuthState = WRITER) {
  const auth = { state, signIn: vi.fn(), signOut: vi.fn() }
  const result = render(
    <MemoryRouter initialEntries={[url]}>
      <AuthContext.Provider value={auth}>
        <App />
      </AuthContext.Provider>
    </MemoryRouter>,
  )
  return { ...result, auth }
}
