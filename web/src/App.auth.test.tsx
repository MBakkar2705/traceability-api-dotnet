// @vitest-environment jsdom

import { cleanup, fireEvent, screen } from '@testing-library/react'
import { afterEach, describe, expect, it } from 'vitest'
import type { AuthState } from './auth/AuthContext'
import { ok, stubApi } from './test/helpers'
import { READER, WRITER, renderApp } from './test/renderApp'

afterEach(cleanup)

const emptyPage = () => ok({ items: [], totalCount: 0, pageNumber: 1, pageSize: 15 })
const station = { code: 'SITE-01', name: 'Reception site 1', capabilities: ['RECEPTION'] }
const batch = {
  batchCode: 'LOT-0000001',
  farmCode: 'F001',
  variety: 'Roma',
  harvestDate: '2026-10-14',
  quantityKg: 500.5,
  status: 'SORTED',
  movements: [],
}
const handlers = {
  '/batches': emptyPage,
  '/farms': emptyPage,
  '/stations': emptyPage,
  '/stations/SITE-01': () => ok(station),
  '/batches/LOT-0000001': () => ok(batch),
}

describe('the sign-in screen', () => {
  it('is all that a user who is not signed in sees, and calls no API', () => {
    const fetchMock = stubApi(handlers)

    renderApp('/farms', { status: 'signedOut' })

    expect(screen.getByRole('heading', { name: 'Connexion' })).toBeTruthy()
    expect(screen.queryByRole('link', { name: 'Fermes' })).toBeNull()
    expect(screen.queryByRole('heading', { name: 'Fermes' })).toBeNull()
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it('has a button that signs in', () => {
    stubApi(handlers)
    const { auth } = renderApp('/batches', { status: 'signedOut' })

    fireEvent.click(screen.getByRole('button', { name: 'Se connecter' }))

    expect(auth.signIn).toHaveBeenCalledTimes(1)
  })

  it('says that the session has expired', () => {
    renderApp('/batches', { status: 'signedOut', reason: 'expired' })

    expect(screen.getByText('Votre session a expiré. Connectez-vous de nouveau.')).toBeTruthy()
  })

  it('says that the sign-in server cannot be reached', () => {
    renderApp('/batches', { status: 'signedOut', reason: 'unreachable' })

    expect(screen.getByRole('alert').textContent).toContain('Impossible de joindre le serveur de connexion.')
  })

  it('does not call the API and does not offer the button while the sign-in is not known yet', () => {
    const fetchMock = stubApi(handlers)

    renderApp('/batches', { status: 'loading' })

    expect(screen.getByRole('status').textContent).toContain('Chargement…')
    expect(screen.queryByRole('button', { name: 'Se connecter' })).toBeNull()
    expect(fetchMock).not.toHaveBeenCalled()
  })
})

describe('the header', () => {
  it('shows who is signed in and a button that signs out', async () => {
    stubApi(handlers)
    const { auth } = renderApp('/batches')

    expect(await screen.findByRole('heading', { name: 'Lots' })).toBeTruthy()
    expect(screen.getByText('writer-test')).toBeTruthy()
    fireEvent.click(screen.getByRole('button', { name: 'Se déconnecter' }))
    expect(auth.signOut).toHaveBeenCalledTimes(1)
  })
})

describe.each<[string, AuthState]>([
  ['a reader', READER],
  ['a user with no role', { status: 'signedIn', userName: 'nobody', roles: ['offline_access'] }],
])('%s', (_name, state) => {
  it.each([
    ['/farms', 'Fermes', 'Nouvelle ferme'],
    ['/batches', 'Lots', 'Nouveau lot'],
    ['/stations', 'Stations', 'Nouvelle station'],
  ])('sees the list %s without the button that writes', async (url, title, buttonName) => {
    stubApi(handlers)

    renderApp(url, state)

    expect(await screen.findByRole('heading', { name: title })).toBeTruthy()
    expect(screen.queryByRole('link', { name: buttonName })).toBeNull()
  })

  it('sees a station without the form that adds a function', async () => {
    stubApi(handlers)

    renderApp('/stations/SITE-01', state)

    expect(await screen.findByText('Reception site 1')).toBeTruthy()
    expect(screen.queryByRole('button', { name: 'Ajouter la fonction' })).toBeNull()
  })

  it('sees a batch without the part that adds a movement', async () => {
    stubApi(handlers)

    renderApp('/batches/LOT-0000001', state)

    expect(await screen.findByText('Roma')).toBeTruthy()
    expect(screen.queryByRole('heading', { name: 'Ajouter un mouvement' })).toBeNull()
    expect(screen.queryByRole('button', { name: /Ajouter le mouvement/ })).toBeNull()
  })

  it.each([
    ['/new-farm', 'Créer la ferme'],
    ['/new-batch', 'Créer le lot'],
    ['/new-station', 'Créer la station'],
  ])('gets a message and no form at %s', (url, buttonName) => {
    stubApi(handlers)

    renderApp(url, state)

    expect(screen.getByText("Vous n'avez pas le droit de saisir des données.")).toBeTruthy()
    expect(screen.queryByRole('button', { name: buttonName })).toBeNull()
  })
})

describe('a writer', () => {
  it.each([
    ['/farms', 'Nouvelle ferme'],
    ['/batches', 'Nouveau lot'],
    ['/stations', 'Nouvelle station'],
  ])('is offered the button that writes in %s', async (url, buttonName) => {
    stubApi(handlers)

    renderApp(url, WRITER)

    expect(await screen.findByRole('link', { name: buttonName })).toBeTruthy()
  })

  it('is offered the form that adds a function and the part that adds a movement', async () => {
    stubApi(handlers)

    renderApp('/stations/SITE-01', WRITER)
    expect(await screen.findByRole('button', { name: 'Ajouter la fonction' })).toBeTruthy()
    cleanup()

    renderApp('/batches/LOT-0000001', WRITER)
    expect(await screen.findByRole('heading', { name: 'Ajouter un mouvement' })).toBeTruthy()
  })

  it('reaches the pages that write', () => {
    stubApi(handlers)

    renderApp('/new-farm', WRITER)

    expect(screen.getByRole('heading', { name: 'Nouvelle ferme' })).toBeTruthy()
    expect(screen.queryByText("Vous n'avez pas le droit de saisir des données.")).toBeNull()
  })
})
