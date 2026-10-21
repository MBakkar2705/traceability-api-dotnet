// @vitest-environment jsdom

import { cleanup, fireEvent, screen } from '@testing-library/react'
import { afterEach, describe, expect, it } from 'vitest'
import { ok, problem, stubApi } from '../test/helpers'
import { renderApp } from '../test/renderApp'

afterEach(cleanup)

const station = { code: 'SITE-01', name: 'Reception site 1', capabilities: ['RECEPTION', 'SORTING'] }

describe('StationPage', () => {
  it('shows the station with its functions in French', async () => {
    stubApi({ '/stations/SITE-01': () => ok(station) })

    renderApp('/stations/SITE-01')

    expect(await screen.findByText('Reception site 1')).toBeTruthy()
    expect(screen.getByRole('heading', { name: 'Station SITE-01' })).toBeTruthy()
    expect(screen.getByText('Réception')).toBeTruthy()
    expect(screen.getByText('Tri')).toBeTruthy()
    expect(screen.getByRole('link', { name: /Retour aux stations/ }).getAttribute('href')).toBe('/stations')
  })

  it('says so when the station has no function', async () => {
    stubApi({ '/stations/SITE-01': () => ok({ ...station, capabilities: [] }) })

    renderApp('/stations/SITE-01')

    expect(await screen.findByText('Aucune fonction déclarée.')).toBeTruthy()
  })

  it('says when the station does not exist', async () => {
    stubApi({ '/stations/SITE-99': () => problem(404, { errorCode: 50102 }) })

    renderApp('/stations/SITE-99')

    expect((await screen.findByRole('alert')).textContent).toContain('Station introuvable.')
  })

  it('opens from the list of stations', async () => {
    stubApi({
      '/stations': () => ok({ items: [{ code: 'SITE-01', name: 'Reception site 1' }], totalCount: 1, pageNumber: 1, pageSize: 15 }),
      '/stations/SITE-01': () => ok(station),
    })

    renderApp('/stations')
    fireEvent.click(await screen.findByRole('link', { name: 'SITE-01' }))

    expect(await screen.findByRole('heading', { name: 'Station SITE-01' })).toBeTruthy()
    expect(await screen.findByText('Réception')).toBeTruthy()
  })
})
