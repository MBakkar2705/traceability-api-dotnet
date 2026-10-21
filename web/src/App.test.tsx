// @vitest-environment jsdom

import { cleanup, fireEvent, screen } from '@testing-library/react'
import { afterEach, describe, expect, it } from 'vitest'
import { ok, stubApi } from './test/helpers'
import { renderApp } from './test/renderApp'

afterEach(cleanup)

const emptyPage = () => ok({ items: [], totalCount: 0, pageNumber: 1, pageSize: 15 })
const handlers = { '/batches': emptyPage, '/farms': emptyPage, '/stations': emptyPage }

describe('App', () => {
  it('sends the home page to the batches', async () => {
    const fetchMock = stubApi(handlers)

    renderApp('/')

    expect(await screen.findByRole('heading', { name: 'Lots' })).toBeTruthy()
    expect(fetchMock.mock.calls[0][0]).toBe('https://localhost:7080/batches?pageNumber=1&pageSize=15')
  })

  it('has a navigation to the three lists, that works', async () => {
    stubApi(handlers)

    renderApp('/batches')
    expect(screen.getByRole('link', { name: 'Lots' }).getAttribute('href')).toBe('/batches')
    expect(screen.getByRole('link', { name: 'Stations' }).getAttribute('href')).toBe('/stations')

    fireEvent.click(screen.getByRole('link', { name: 'Fermes' }))
    expect(await screen.findByRole('heading', { name: 'Fermes' })).toBeTruthy()

    fireEvent.click(screen.getByRole('link', { name: 'Stations' }))
    expect(await screen.findByRole('heading', { name: 'Stations' })).toBeTruthy()
  })

  it('shows a page for an address that matches no screen', () => {
    renderApp('/nimportequoi')

    expect(screen.getByRole('heading', { name: 'Page introuvable' })).toBeTruthy()
    expect(screen.getByRole('link', { name: "Retour à l'accueil" }).getAttribute('href')).toBe('/')
  })
})
