// @vitest-environment jsdom

import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { MemoryRouter, Route, Routes } from 'react-router'
import { afterEach, describe, expect, it } from 'vitest'
import { PAGE_SIZE } from '../config'
import { ok, problem, stubFetch } from '../test/helpers'
import FarmsPage from './FarmsPage'

afterEach(cleanup)

const BASE = 'https://localhost:7080'
const TOTAL = PAGE_SIZE * 2 + 5 // 3 pages: two full pages, then 5 farms
const query = (pageNumber: number) => `pageNumber=${pageNumber}&pageSize=${PAGE_SIZE}`

function renderPage(url = '/farms') {
  return render(
    <MemoryRouter initialEntries={[url]}>
      <Routes>
        <Route path="farms" element={<FarmsPage />} />
      </Routes>
    </MemoryRouter>,
  )
}

// An answer of the API for the page asked in the address.
function farmsPage(url: string) {
  const pageNumber = Number(new URL(url).searchParams.get('pageNumber'))
  const count = pageNumber === 3 ? 5 : PAGE_SIZE
  const items = Array.from({ length: count }, (_, i) => ({
    code: `F${pageNumber}-${i + 1}`,
    name: `Ferme ${pageNumber}-${i + 1}`,
    region: 'Souss',
  }))
  return ok({ items, totalCount: TOTAL, pageNumber, pageSize: PAGE_SIZE })
}

const button = (name: RegExp) => screen.getByRole('button', { name }) as HTMLButtonElement

describe('FarmsPage', () => {
  it('shows loading, then the farms', async () => {
    const fetchMock = stubFetch((url) => Promise.resolve(farmsPage(url)))

    renderPage()

    expect(screen.getByRole('status').textContent).toBe('Chargement…')
    expect(await screen.findByText('Ferme 1-1')).toBeTruthy()
    expect(screen.getByText('F1-1')).toBeTruthy()
    expect(screen.getAllByText('Souss')).toHaveLength(PAGE_SIZE)
    expect(screen.queryByRole('status')).toBeNull()
    expect(fetchMock.mock.calls[0][0]).toBe(`${BASE}/farms?${query(1)}`)
  })

  it('says so when there is no farm', async () => {
    stubFetch(() => Promise.resolve(ok({ items: [], totalCount: 0, pageNumber: 1, pageSize: PAGE_SIZE })))

    renderPage()

    expect(await screen.findByText('Aucune ferme enregistrée.')).toBeTruthy()
  })

  it('says so when the page is beyond the end, and "previous" goes back to the last real page', async () => {
    const fetchMock = stubFetch((url) =>
      Promise.resolve(
        new URL(url).searchParams.get('pageNumber') === '9'
          ? ok({ items: [], totalCount: TOTAL, pageNumber: 9, pageSize: PAGE_SIZE })
          : farmsPage(url),
      ),
    )

    renderPage('/farms?page=9')

    expect(await screen.findByText('Cette page est vide.')).toBeTruthy()
    expect(fetchMock.mock.calls[0][0]).toBe(`${BASE}/farms?${query(9)}`)
    expect(button(/Précédent/).disabled).toBe(false)

    fireEvent.click(button(/Précédent/))

    await screen.findByText('F3-1')
    expect(fetchMock.mock.calls[1][0]).toBe(`${BASE}/farms?${query(3)}`)
  })

  it('asks page 1 when the page in the address is not a number', async () => {
    const fetchMock = stubFetch((url) => Promise.resolve(farmsPage(url)))

    renderPage('/farms?page=abc')

    await screen.findByText('Ferme 1-1')
    expect(fetchMock.mock.calls[0][0]).toBe(`${BASE}/farms?${query(1)}`)
  })

  it('shows the error in French, with the trace id of an unexpected error', async () => {
    stubFetch(() => Promise.resolve(problem(500)))

    renderPage()

    expect((await screen.findByRole('alert')).textContent).toContain('Erreur inattendue du serveur.')
    expect(screen.getByRole('alert').textContent).toContain('Référence : 00-abc')
  })

  it('says when the API cannot be reached', async () => {
    stubFetch(() => Promise.reject(new TypeError('Failed to fetch')))

    renderPage()

    expect((await screen.findByRole('alert')).textContent).toContain("Impossible de joindre l'API. Est-elle lancée ?")
  })

  it('goes to the next page and back, with the buttons disabled at both ends', async () => {
    const fetchMock = stubFetch((url) => Promise.resolve(farmsPage(url)))

    renderPage()
    await screen.findByText('Ferme 1-1')
    expect(screen.getByText(/Page 1 sur 3/)).toBeTruthy()
    expect(button(/Début/).disabled).toBe(true)
    expect(button(/Précédent/).disabled).toBe(true)
    expect(button(/Suivant/).disabled).toBe(false)

    fireEvent.click(button(/Suivant/))
    await screen.findByText('Ferme 2-1')
    expect(fetchMock.mock.calls[1][0]).toBe(`${BASE}/farms?${query(2)}`)

    fireEvent.click(button(/Suivant/))
    await screen.findByText('Ferme 3-1')
    expect(screen.getByText(/Page 3 sur 3/)).toBeTruthy()
    expect(button(/Suivant/).disabled).toBe(true)
    expect(button(/Fin/).disabled).toBe(true)

    fireEvent.click(button(/Précédent/))
    await screen.findByText('Ferme 2-1')
  })

  it('jumps straight to the first and to the last page', async () => {
    const fetchMock = stubFetch((url) => Promise.resolve(farmsPage(url)))

    renderPage('/farms?page=2')
    await screen.findByText('Ferme 2-1')

    fireEvent.click(button(/Fin/))
    await screen.findByText('Ferme 3-1')
    expect(fetchMock.mock.calls[1][0]).toBe(`${BASE}/farms?${query(3)}`)

    fireEvent.click(button(/Début/))
    await screen.findByText('Ferme 1-1')
    expect(fetchMock.mock.calls[2][0]).toBe(`${BASE}/farms?${query(1)}`)
  })
})
