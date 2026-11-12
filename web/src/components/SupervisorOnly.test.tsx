// @vitest-environment jsdom

import { cleanup, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { AuthContext } from '../auth/AuthContext'
import type { AuthState } from '../auth/AuthContext'
import SupervisorOnly from './SupervisorOnly'

afterEach(cleanup)

function renderWith(state: AuthState) {
  render(
    <AuthContext.Provider value={{ state, signIn: vi.fn(), signOut: vi.fn() }}>
      <SupervisorOnly>
        <button type="button">Correct</button>
      </SupervisorOnly>
    </AuthContext.Provider>,
  )
}

describe('SupervisorOnly', () => {
  it('shows what corrects to a user who has the supervisor role', () => {
    renderWith({ status: 'signedIn', userName: 'a', roles: ['offline_access', 'supervisor'] })

    expect(screen.getByRole('button', { name: 'Correct' })).toBeTruthy()
  })

  it.each<[string, AuthState]>([
    ['a writer', { status: 'signedIn', userName: 'a', roles: ['writer'] }],
    ['a reader', { status: 'signedIn', userName: 'a', roles: ['reader'] }],
    ['a user with no role', { status: 'signedIn', userName: 'a', roles: [] }],
    ['nobody is signed in', { status: 'signedOut' }],
    ['the sign-in is not known yet', { status: 'loading' }],
  ])('hides it from %s', (_name, state) => {
    renderWith(state)

    expect(screen.queryByRole('button', { name: 'Correct' })).toBeNull()
  })

  it('hides it when there is no provider at all', () => {
    render(
      <SupervisorOnly>
        <button type="button">Correct</button>
      </SupervisorOnly>,
    )

    expect(screen.queryByRole('button', { name: 'Correct' })).toBeNull()
  })
})
