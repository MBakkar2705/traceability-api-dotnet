// @vitest-environment jsdom

import { cleanup, screen } from '@testing-library/react'
import { afterEach, describe, expect, it } from 'vitest'
import { ok, problem, stubApi } from '../test/helpers'
import { renderApp } from '../test/renderApp'

afterEach(cleanup)

const BASE = 'https://localhost:7080'

const batch = {
  batchCode: 'LOT-0000001',
  farmCode: 'F001',
  variety: 'Roma',
  harvestDate: '2026-10-14',
  quantityKg: 500.5,
  status: 'SHIPPED',
  movements: [
    { movementId: 1, movementType: 'RECEPTION', stationCode: 'SITE-01', quantityKg: 500.5, occurredAt: '2026-10-14T08:30:00Z' },
    { movementId: 2, movementType: 'SORTING', stationCode: 'SITE-02', quantityKg: 480, occurredAt: '2026-10-14T10:05:30.1234567Z' },
  ],
}

describe('BatchPage', () => {
  it('shows the batch and its journey in the order recorded, times in UTC', async () => {
    stubApi({ '/batches/LOT-0000001': () => ok(batch) })

    renderApp('/batches/LOT-0000001')

    expect(await screen.findByText('Roma')).toBeTruthy()
    expect(screen.getByRole('heading', { name: 'Lot LOT-0000001' })).toBeTruthy()
    expect(screen.getByText('14/10/2026')).toBeTruthy()
    expect(screen.getByText('Expédié')).toBeTruthy()

    const rows = screen.getAllByRole('row')
    expect(rows).toHaveLength(3) // the header, then the two movements
    expect(rows[1].textContent).toContain('Réception')
    expect(rows[1].textContent).toContain('SITE-01')
    expect(rows[1].textContent).toContain('500,50 kg')
    expect(rows[1].textContent).toContain('14/10/2026 08:30:00 UTC')
    expect(rows[2].textContent).toContain('Tri')
    expect(rows[2].textContent).toContain('SITE-02')
    expect(rows[2].textContent).toContain('480,00 kg')
    expect(rows[2].textContent).toContain('14/10/2026 10:05:30 UTC')
  })

  it('links each movement to its station', async () => {
    stubApi({ '/batches/LOT-0000001': () => ok(batch) })

    renderApp('/batches/LOT-0000001')

    expect((await screen.findByRole('link', { name: 'SITE-02' })).getAttribute('href')).toBe('/stations/SITE-02')
    expect(screen.getByRole('link', { name: /Retour aux lots/ }).getAttribute('href')).toBe('/batches')
  })

  it('says when the batch has no movement', async () => {
    stubApi({ '/batches/LOT-0000001': () => ok({ ...batch, movements: [] }) })

    renderApp('/batches/LOT-0000001')

    expect(await screen.findByText('Aucun mouvement enregistré.')).toBeTruthy()
  })

  it('says when the batch does not exist', async () => {
    stubApi({ '/batches/LOT-9': () => problem(404, { errorCode: 50100 }) })

    renderApp('/batches/LOT-9')

    expect((await screen.findByRole('alert')).textContent).toContain('Lot introuvable.')
  })

  it('writes a code with a space in the address of the API without breaking it', async () => {
    const fetchMock = stubApi({})

    renderApp('/batches/A%20B')

    expect(await screen.findByRole('alert')).toBeTruthy()
    expect(fetchMock.mock.calls[0][0]).toBe(`${BASE}/batches/A%20B`)
    expect(screen.getByRole('heading', { name: 'Lot A B' })).toBeTruthy()
  })
})
