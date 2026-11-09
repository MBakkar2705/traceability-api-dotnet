// @vitest-environment jsdom

import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import type { User } from 'oidc-client-ts'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { tokenWithRoles } from '../test/fakeToken'
import { useAuth } from './AuthContext'
import AuthProvider from './AuthProvider'
import { getAccessToken, setAccessToken } from './token'

// A fake of the object of the library: no Keycloak, no network. The tests play its events by
// calling the functions that the provider gave to it.
const mocks = vi.hoisted(() => {
  const listeners: Record<'loaded' | 'unloaded' | 'expired', (arg?: unknown) => void> = {
    loaded: () => undefined,
    unloaded: () => undefined,
    expired: () => undefined,
  }
  const removers = { loaded: vi.fn(), unloaded: vi.fn(), expired: vi.fn() }
  const manager = {
    getUser: vi.fn(),
    signinRedirect: vi.fn(),
    signoutRedirect: vi.fn(),
    removeUser: vi.fn(),
    events: {
      addUserLoaded: vi.fn((callback: (arg?: unknown) => void) => {
        listeners.loaded = callback
        return removers.loaded
      }),
      addUserUnloaded: vi.fn((callback: (arg?: unknown) => void) => {
        listeners.unloaded = callback
        return removers.unloaded
      }),
      addAccessTokenExpired: vi.fn((callback: (arg?: unknown) => void) => {
        listeners.expired = callback
        return removers.expired
      }),
    },
  }
  return { listeners, removers, manager }
})

vi.mock('./userManager', () => ({ getUserManager: () => mocks.manager }))

function userWith(...roles: string[]): User {
  return {
    access_token: tokenWithRoles(...roles),
    expired: false,
    profile: { preferred_username: 'writer-test' },
  } as unknown as User
}

function Probe() {
  const { state, signIn, signOut } = useAuth()
  return (
    <div>
      <p data-testid="state">{JSON.stringify(state)}</p>
      <button type="button" onClick={signIn}>
        in
      </button>
      <button type="button" onClick={signOut}>
        out
      </button>
    </div>
  )
}

function renderProvider() {
  return render(
    <AuthProvider>
      <Probe />
    </AuthProvider>,
  )
}

const stateOf = () => JSON.parse(screen.getByTestId('state').textContent ?? '')

beforeEach(() => {
  vi.clearAllMocks()
  mocks.manager.signinRedirect.mockResolvedValue(undefined)
  mocks.manager.signoutRedirect.mockResolvedValue(undefined)
  mocks.manager.removeUser.mockResolvedValue(undefined)
})

afterEach(() => {
  cleanup()
  setAccessToken(null)
})

describe('AuthProvider', () => {
  it('is loading until the library has answered', () => {
    mocks.manager.getUser.mockReturnValue(new Promise(() => undefined))

    renderProvider()

    expect(stateOf()).toEqual({ status: 'loading' })
  })

  it('is signed out when the library has no user', async () => {
    mocks.manager.getUser.mockResolvedValue(null)

    renderProvider()

    await waitFor(() => expect(stateOf()).toEqual({ status: 'signedOut' }))
    expect(getAccessToken()).toBeNull()
  })

  it('is signed out when the library cannot read the user', async () => {
    mocks.manager.getUser.mockRejectedValue(new Error('broken'))

    renderProvider()

    await waitFor(() => expect(stateOf()).toEqual({ status: 'signedOut' }))
  })

  it('is signed out when the user in memory has expired', async () => {
    mocks.manager.getUser.mockResolvedValue({ ...userWith('writer'), expired: true })

    renderProvider()

    await waitFor(() => expect(stateOf()).toEqual({ status: 'signedOut' }))
    expect(getAccessToken()).toBeNull()
  })

  it('is signed in with the name and the roles of the user, and gives the token to the API client', async () => {
    const user = userWith('writer', 'offline_access')
    mocks.manager.getUser.mockResolvedValue(user)

    renderProvider()

    await waitFor(() =>
      expect(stateOf()).toEqual({ status: 'signedIn', userName: 'writer-test', roles: ['writer', 'offline_access'] }),
    )
    expect(getAccessToken()).toBe(user.access_token)
  })

  it('follows a renewal: the new token and its roles replace the old ones', async () => {
    mocks.manager.getUser.mockResolvedValue(userWith('writer'))
    renderProvider()
    await waitFor(() => expect(stateOf().status).toBe('signedIn'))

    const renewed = userWith('reader')
    act(() => mocks.listeners.loaded(renewed))

    expect(stateOf().roles).toEqual(['reader'])
    expect(getAccessToken()).toBe(renewed.access_token)
  })

  it('is signed out, with the reason, when the token ran out', async () => {
    mocks.manager.getUser.mockResolvedValue(userWith('writer'))
    renderProvider()
    await waitFor(() => expect(stateOf().status).toBe('signedIn'))

    act(() => mocks.listeners.expired())

    expect(stateOf()).toEqual({ status: 'signedOut', reason: 'expired' })
    expect(getAccessToken()).toBeNull()
  })

  it('is signed out when the library removes the user', async () => {
    mocks.manager.getUser.mockResolvedValue(userWith('writer'))
    renderProvider()
    await waitFor(() => expect(stateOf().status).toBe('signedIn'))

    act(() => mocks.listeners.unloaded())

    expect(stateOf()).toEqual({ status: 'signedOut' })
    expect(getAccessToken()).toBeNull()
  })

  it('sends the user to Keycloak to sign in', async () => {
    mocks.manager.getUser.mockResolvedValue(null)
    renderProvider()
    await waitFor(() => expect(stateOf().status).toBe('signedOut'))

    fireEvent.click(screen.getByRole('button', { name: 'in' }))

    expect(mocks.manager.signinRedirect).toHaveBeenCalledTimes(1)
  })

  it('says that Keycloak cannot be reached when the redirect fails', async () => {
    mocks.manager.getUser.mockResolvedValue(null)
    mocks.manager.signinRedirect.mockRejectedValue(new Error('network'))
    renderProvider()
    await waitFor(() => expect(stateOf().status).toBe('signedOut'))

    fireEvent.click(screen.getByRole('button', { name: 'in' }))

    await waitFor(() => expect(stateOf()).toEqual({ status: 'signedOut', reason: 'unreachable' }))
  })

  it('ends the session at Keycloak to sign out', async () => {
    mocks.manager.getUser.mockResolvedValue(userWith('writer'))
    renderProvider()
    await waitFor(() => expect(stateOf().status).toBe('signedIn'))

    fireEvent.click(screen.getByRole('button', { name: 'out' }))

    expect(mocks.manager.signoutRedirect).toHaveBeenCalledTimes(1)
    expect(mocks.manager.removeUser).not.toHaveBeenCalled()
  })

  it('removes the local sign-in when the redirect to sign out fails', async () => {
    mocks.manager.getUser.mockResolvedValue(userWith('writer'))
    mocks.manager.signoutRedirect.mockRejectedValue(new Error('network'))
    renderProvider()
    await waitFor(() => expect(stateOf().status).toBe('signedIn'))

    fireEvent.click(screen.getByRole('button', { name: 'out' }))

    await waitFor(() => expect(mocks.manager.removeUser).toHaveBeenCalledTimes(1))
  })

  it('stops listening to the library when it is removed from the screen', async () => {
    mocks.manager.getUser.mockResolvedValue(null)
    const { unmount } = renderProvider()
    await waitFor(() => expect(stateOf().status).toBe('signedOut'))

    unmount()

    expect(mocks.removers.loaded).toHaveBeenCalledTimes(1)
    expect(mocks.removers.unloaded).toHaveBeenCalledTimes(1)
    expect(mocks.removers.expired).toHaveBeenCalledTimes(1)
  })
})
