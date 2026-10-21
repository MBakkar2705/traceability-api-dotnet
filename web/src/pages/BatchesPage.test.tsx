// @vitest-environment jsdom

import { cleanup, fireEvent, screen, within } from '@testing-library/react'
import { afterEach, describe, expect, it } from 'vitest'
import { ok, problem, stubApi } from '../test/helpers'
import { renderApp } from '../test/renderApp'

afterEach(cleanup)

const BASE = 'https://localhost:7080'
const NO_FILTER = `${BASE}/batches?pageNumber=1&pageSize=15`

// 100 batches in all (7 pages of 15), the page asked is read in the address.
function batchesPage(url: URL) {
  const pageNumber = Number(url.searchParams.get('pageNumber'))
  const items = Array.from({ length: 15 }, (_, i) => ({
    batchCode: `LOT-${pageNumber}-${i + 1}`,
    farmCode: 'F001',
    variety: 'Roma',
    harvestDate: '2026-10-14',
    quantityKg: 500.5,
    status: 'SHIPPED',
  }))
  return ok({ items, totalCount: 100, pageNumber, pageSize: 15 })
}

const emptyPage = () => ok({ items: [], totalCount: 0, pageNumber: 1, pageSize: 15 })
const urls = (mock: { mock: { calls: unknown[][] } }) => mock.mock.calls.map((call) => call[0])

describe('BatchesPage', () => {
  it('says that the list can take a few seconds while it loads', () => {
    stubApi({ '/batches': batchesPage })

    renderApp('/batches')

    expect(screen.getByRole('status').textContent).toContain('La liste des lots peut prendre quelques secondes.')
  })

  it('lists the batches in French, each code being a link to the batch', async () => {
    const fetchMock = stubApi({ '/batches': batchesPage })

    renderApp('/batches')

    expect(await screen.findByText('LOT-1-1')).toBeTruthy()
    expect(urls(fetchMock)[0]).toBe(NO_FILTER)
    expect(screen.getByRole('link', { name: 'LOT-1-1' }).getAttribute('href')).toBe('/batches/LOT-1-1')
    const table = within(screen.getByRole('table'))
    expect(table.getAllByText('Expédié')).toHaveLength(15)
    expect(table.getAllByText('500,50 kg')).toHaveLength(15)
    expect(table.getAllByText('14/10/2026')).toHaveLength(15)
    expect(screen.getByText(/Page 1 sur 7/)).toBeTruthy()
  })

  it('asks the API for the filters, without the spaces around the farm code', async () => {
    const fetchMock = stubApi({ '/batches': batchesPage })

    renderApp('/batches')
    await screen.findByText('LOT-1-1')
    fireEvent.change(screen.getByLabelText('Statut'), { target: { value: 'SHIPPED' } })
    fireEvent.change(screen.getByLabelText('Ferme'), { target: { value: ' F001 ' } })
    fireEvent.click(screen.getByRole('button', { name: 'Filtrer' }))

    await screen.findByText('LOT-1-1')
    expect(urls(fetchMock).at(-1)).toBe(`${BASE}/batches?status=SHIPPED&farmCode=F001&pageNumber=1&pageSize=15`)
    expect((screen.getByLabelText('Statut') as HTMLSelectElement).value).toBe('SHIPPED')
    expect((screen.getByLabelText('Ferme') as HTMLInputElement).value).toBe('F001')
  })

  it('keeps the filters when the page changes, and goes back to page 1 when they are applied', async () => {
    const fetchMock = stubApi({ '/batches': batchesPage })

    renderApp('/batches?status=SHIPPED&farmCode=F001&page=2')
    await screen.findByText('LOT-2-1')

    fireEvent.click(screen.getByRole('button', { name: /Suivant/ }))
    await screen.findByText('LOT-3-1')
    expect(urls(fetchMock).at(-1)).toBe(`${BASE}/batches?status=SHIPPED&farmCode=F001&pageNumber=3&pageSize=15`)

    fireEvent.click(screen.getByRole('button', { name: 'Filtrer' }))
    await screen.findByText('LOT-1-1')
    expect(urls(fetchMock).at(-1)).toBe(`${BASE}/batches?status=SHIPPED&farmCode=F001&pageNumber=1&pageSize=15`)
  })

  it('clears the filters', async () => {
    const fetchMock = stubApi({ '/batches': batchesPage })

    renderApp('/batches?status=SHIPPED&farmCode=F001')
    await screen.findByText('LOT-1-1')

    fireEvent.click(screen.getByRole('button', { name: 'Effacer les filtres' }))

    await screen.findByText('LOT-1-1')
    expect(urls(fetchMock).at(-1)).toBe(NO_FILTER)
    expect(screen.queryByRole('button', { name: 'Effacer les filtres' })).toBeNull()
  })

  it('does not offer to clear filters when there are none', async () => {
    stubApi({ '/batches': batchesPage })

    renderApp('/batches')
    await screen.findByText('LOT-1-1')

    expect(screen.queryByRole('button', { name: 'Effacer les filtres' })).toBeNull()
  })

  it('says whether the list is empty or the filters match nothing', async () => {
    stubApi({ '/batches': emptyPage })

    renderApp('/batches?status=PACKED')

    expect(await screen.findByText('Aucun lot ne correspond à ces filtres.')).toBeTruthy()

    cleanup()
    renderApp('/batches')

    expect(await screen.findByText('Aucun lot enregistré.')).toBeTruthy()
  })

  it('says in French that the farm or the status is unknown', async () => {
    stubApi({
      '/batches': (url) =>
        url.searchParams.get('status') === 'LOST' ? problem(400, { errorCode: 50403 }) : problem(404, { errorCode: 50101 }),
    })

    renderApp('/batches?farmCode=F999')
    expect((await screen.findByRole('alert')).textContent).toContain('Ferme introuvable.')

    cleanup()
    renderApp('/batches?status=LOST')
    expect((await screen.findByRole('alert')).textContent).toContain('Statut inconnu.')
  })
})
