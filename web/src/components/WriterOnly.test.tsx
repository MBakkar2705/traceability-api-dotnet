// @vitest-environment jsdom

import { cleanup, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { AuthContext } from '../auth/AuthContext'
import type { AuthState } from '../auth/AuthContext'
import WriterOnly from './WriterOnly'

afterEach(cleanup)

function renderWith(state: AuthState, fallback?: string) {
  render(
    <AuthContext.Provider value={{ state, signIn: vi.fn(), signOut: vi.fn() }}>
      <WriterOnly fallback={fallback}>
        <button type="button">Write</button>
      </WriterOnly>
    </AuthContext.Provider>,
  )
}

describe('WriterOnly', () => {
  it('shows what writes to a user who has the writer role', () => {
    renderWith({ status: 'signedIn', userName: 'a', roles: ['offline_access', 'writer'] })

    expect(screen.getByRole('button', { name: 'Write' })).toBeTruthy()
  })

  it('hides it from a reader, and shows the fallback instead when there is one', () => {
    renderWith({ status: 'signedIn', userName: 'a', roles: ['reader'] }, 'No right')

    expect(screen.queryByRole('button', { name: 'Write' })).toBeNull()
    expect(screen.getByText('No right')).toBeTruthy()
  })

  it('shows nothing by default to a user who cannot write', () => {
    renderWith({ status: 'signedIn', userName: 'a', roles: [] })

    expect(screen.queryByRole('button', { name: 'Write' })).toBeNull()
  })

  it.each<[string, AuthState]>([
    ['nobody is signed in', { status: 'signedOut' }],
    ['the sign-in is not known yet', { status: 'loading' }],
  ])('hides it when %s', (_name, state) => {
    renderWith(state)

    expect(screen.queryByRole('button', { name: 'Write' })).toBeNull()
  })

  it('hides it when there is no provider at all', () => {
    render(
      <WriterOnly>
        <button type="button">Write</button>
      </WriterOnly>,
    )

    expect(screen.queryByRole('button', { name: 'Write' })).toBeNull()
  })
})
