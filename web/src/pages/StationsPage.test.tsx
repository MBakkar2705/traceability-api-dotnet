// @vitest-environment jsdom

import { cleanup, screen } from '@testing-library/react'
import { afterEach, describe, expect, it } from 'vitest'
import { ok, stubApi } from '../test/helpers'
import { renderApp } from '../test/renderApp'

afterEach(cleanup)

const page = (items: unknown[]) => ({ items, totalCount: items.length, pageNumber: 1, pageSize: 15 })

describe('StationsPage', () => {
  it('lists the stations, each code being a link to the station', async () => {
    stubApi({
      '/stations': () =>
        ok(page([{ code: 'SITE-01', name: 'Reception site 1' }, { code: 'PCK-01', name: 'Packing line 1' }])),
    })

    renderApp('/stations')

    expect(await screen.findByText('Reception site 1')).toBeTruthy()
    expect(screen.getByRole('heading', { name: 'Stations' })).toBeTruthy()
    expect(screen.getByRole('link', { name: 'SITE-01' }).getAttribute('href')).toBe('/stations/SITE-01')
    expect(screen.getByRole('link', { name: 'PCK-01' }).getAttribute('href')).toBe('/stations/PCK-01')
  })

  it('says so when there is no station', async () => {
    stubApi({ '/stations': () => ok(page([])) })

    renderApp('/stations')

    expect(await screen.findByText('Aucune station enregistrée.')).toBeTruthy()
  })
})
