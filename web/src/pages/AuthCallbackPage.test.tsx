// @vitest-environment jsdom

import { cleanup, render, screen } from '@testing-library/react'
import { StrictMode } from 'react'
import { MemoryRouter } from 'react-router'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import App from '../App'
import { AuthContext } from '../auth/AuthContext'
import { ok, stubApi } from '../test/helpers'
import { WRITER, renderApp } from '../test/renderApp'

// A fake of the object of the library: the code of the address is not exchanged for real here.
const mocks = vi.hoisted(() => ({ signinRedirectCallback: vi.fn() }))
vi.mock('../auth/userManager', () => ({ getUserManager: () => mocks }))

afterEach(cleanup)

beforeEach(() => {
  vi.clearAllMocks()
  stubApi({ '/batches': () => ok({ items: [], totalCount: 0, pageNumber: 1, pageSize: 15 }) })
})

describe('AuthCallbackPage', () => {
  it('says that the sign-in is going on while the library works', () => {
    mocks.signinRedirectCallback.mockReturnValue(new Promise(() => undefined))

    renderApp('/auth/callback?code=abc&state=xyz')

    expect(screen.getByRole('status').textContent).toContain('Connexion en cours.')
  })

  it('goes to the batches once the library has taken the tokens', async () => {
    mocks.signinRedirectCallback.mockResolvedValue({})

    renderApp('/auth/callback?code=abc&state=xyz')

    expect(await screen.findByRole('heading', { name: 'Lots' })).toBeTruthy()
    expect(mocks.signinRedirectCallback).toHaveBeenCalledTimes(1)
  })

  it('says that the sign-in failed and offers the way back', async () => {
    mocks.signinRedirectCallback.mockRejectedValue(new Error('No matching state found in storage'))

    renderApp('/auth/callback')

    expect((await screen.findByRole('alert')).textContent).toContain('La connexion a échoué.')
    expect(screen.getByRole('link', { name: "Retour à l'accueil" }).getAttribute('href')).toBe('/')
  })

  it('uses the code only once even when React runs the effect twice (development)', async () => {
    mocks.signinRedirectCallback.mockResolvedValue({})

    render(
      <StrictMode>
        <MemoryRouter initialEntries={['/auth/callback?code=abc&state=xyz']}>
          <AuthContext.Provider value={{ state: WRITER, signIn: vi.fn(), signOut: vi.fn() }}>
            <App />
          </AuthContext.Provider>
        </MemoryRouter>
      </StrictMode>,
    )

    expect(await screen.findByRole('heading', { name: 'Lots' })).toBeTruthy()
    expect(mocks.signinRedirectCallback).toHaveBeenCalledTimes(1)
  })
})
