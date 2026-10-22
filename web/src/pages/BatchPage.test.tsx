// @vitest-environment jsdom

import { act, cleanup, fireEvent, screen } from '@testing-library/react'
import { afterEach, describe, expect, it } from 'vitest'
import { created, deferred, ok, problem, stubApi, stubFetch } from '../test/helpers'
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

// A batch that has just been received: the next movement is the sorting.
const received = { ...batch, status: 'RECEIVED', movements: [batch.movements[0]] }

describe('BatchPage, adding a movement', () => {
  const TYPE = 'Type de mouvement'
  const STATION = 'Code de la station'
  const QUANTITY = 'Quantité (kg)'
  const TIME = 'Date et heure (UTC)'

  function fill(label: string, value: string) {
    fireEvent.change(screen.getByLabelText(label), { target: { value } })
  }

  function add() {
    fireEvent.click(screen.getByRole('button', { name: 'Ajouter le mouvement' }))
  }

  const valueOf = (label: string) => (screen.getByLabelText(label) as HTMLInputElement).value

  // The text of a field with its messages (the label, the field and the messages under it).
  function fieldText(label: string): string {
    return screen.getByLabelText(label).closest('div')!.textContent
  }

  // The requests that are not the POST: the reads of the batch.
  const reads = (api: ReturnType<typeof stubFetch>) => api.mock.calls.filter(([, init]) => init?.method !== 'POST')

  it('shows the form: the next step, the current quantity and the current time are already filled in', async () => {
    stubApi({ '/batches/LOT-0000001': () => ok(received) })

    renderApp('/batches/LOT-0000001')
    await screen.findByText('Roma')

    expect(valueOf(TYPE)).toBe('SORTING')
    expect(valueOf(QUANTITY)).toBe('500.5')
    expect(valueOf(STATION)).toBe('')
    expect(valueOf(TIME)).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/)
    expect(screen.getByRole('button', { name: 'Ajouter le mouvement' })).toBeTruthy()
  })

  it.each([
    ['SORTED', 'PACKING'],
    ['PACKED', 'SHIPMENT'],
  ])('proposes the step after the status %s: %s', async (status, next) => {
    stubApi({ '/batches/LOT-0000001': () => ok({ ...received, status }) })

    renderApp('/batches/LOT-0000001')
    await screen.findByText('Roma')

    expect(valueOf(TYPE)).toBe(next)
  })

  it('has no form when the batch is shipped, and says why', async () => {
    stubApi({ '/batches/LOT-0000001': () => ok(batch) })

    renderApp('/batches/LOT-0000001')
    await screen.findByText('Roma')

    expect(screen.getByText("Ce lot est expédié : aucun mouvement n'est plus possible.")).toBeTruthy()
    expect(screen.queryByRole('button', { name: 'Ajouter le mouvement' })).toBeNull()
  })

  it('adds the movement with POST, reads the batch again, and starts the form again for the next step', async () => {
    let current = received
    const api = stubApi({
      '/batches/LOT-0000001': () => ok(current),
      '/batches/LOT-0000001/movements': () => {
        current = {
          ...received,
          status: 'SORTED',
          quantityKg: 480,
          movements: [
            ...received.movements,
            { movementId: 2, movementType: 'SORTING', stationCode: 'SITE-02', quantityKg: 480, occurredAt: '2026-10-22T09:00:00Z' },
          ],
        }
        return created()
      },
    })
    renderApp('/batches/LOT-0000001')
    await screen.findByText('Roma')

    fill(STATION, 'SITE-02')
    fill(QUANTITY, '480')
    fill(TIME, '2026-10-22T09:00')
    add()

    expect(await screen.findByText('Mouvement Tri ajouté.')).toBeTruthy()
    // The batch is read again: its new status and its new line in the journey.
    expect(await screen.findByText('Trié')).toBeTruthy()
    expect(screen.getAllByRole('row')).toHaveLength(3)
    const post = api.mock.calls.find(([, init]) => init?.method === 'POST')!
    expect(post[0]).toBe('https://localhost:7080/batches/LOT-0000001/movements')
    expect(JSON.parse(String(post[1]?.body))).toEqual({
      stationCode: 'SITE-02',
      movementType: 'SORTING',
      quantityKg: 480,
      occurredAt: '2026-10-22T09:00:00Z',
    })
    // The form starts again: the next step, the new quantity, no station.
    expect(valueOf(TYPE)).toBe('PACKING')
    expect(valueOf(QUANTITY)).toBe('480')
    expect(valueOf(STATION)).toBe('')
  })

  it('says in French that the step is not the next one, keeps what was typed, and does not read the batch again', async () => {
    const api = stubApi({
      '/batches/LOT-0000001': () => ok(received),
      '/batches/LOT-0000001/movements': () => problem(409, { errorCode: 50301 }),
    })
    renderApp('/batches/LOT-0000001')
    await screen.findByText('Roma')

    fill(STATION, 'SITE-02')
    add()

    expect((await screen.findByRole('alert')).textContent).toContain("Ce mouvement n'est pas l'étape suivante du lot.")
    expect(valueOf(STATION)).toBe('SITE-02')
    expect(reads(api)).toHaveLength(1)
  })

  it('shows the messages of an error of shape under the right fields', async () => {
    const errors = { stationCode: ['The field is required.'], quantityKg: ['The field is required.'] }
    stubApi({
      '/batches/LOT-0000001': () => ok(received),
      '/batches/LOT-0000001/movements': () => problem(400, { errors }),
    })
    renderApp('/batches/LOT-0000001')
    await screen.findByText('Roma')

    fill(STATION, 'SITE-02')
    add()

    const alert = await screen.findByRole('alert')
    expect(alert.textContent).toContain('Certains champs sont invalides.')
    expect(alert.textContent).not.toContain('Champ obligatoire.')
    expect(fieldText(STATION)).toContain('Champ obligatoire.')
    expect(fieldText(QUANTITY)).toContain('Champ obligatoire.')
    expect(fieldText(TIME)).not.toContain('Champ obligatoire.')
  })

  it('disables the button while sending, and sends only one request when it is clicked twice', async () => {
    const answer = deferred<Response>()
    const api = stubFetch((address) =>
      address.endsWith('/movements') ? answer.promise : Promise.resolve(ok(received)),
    )
    renderApp('/batches/LOT-0000001')
    await screen.findByText('Roma')

    fill(STATION, 'SITE-02')
    const button = screen.getByRole('button', { name: 'Ajouter le mouvement' })
    fireEvent.click(button)
    fireEvent.click(button)

    expect(api.mock.calls.filter(([, init]) => init?.method === 'POST')).toHaveLength(1)
    expect((screen.getByRole('button', { name: 'Envoi…' }) as HTMLButtonElement).disabled).toBe(true)

    await act(async () => answer.resolve(created()))
    expect(await screen.findByText('Mouvement Tri ajouté.')).toBeTruthy()
  })

  it('says that the movement may have been saved when the API does not answer', async () => {
    stubFetch((address) =>
      address.endsWith('/movements') ? Promise.reject(new TypeError('Failed to fetch')) : Promise.resolve(ok(received)),
    )
    renderApp('/batches/LOT-0000001')
    await screen.findByText('Roma')

    fill(STATION, 'SITE-02')
    add()

    expect((await screen.findByRole('alert')).textContent).toContain("l'enregistrement a peut-être eu lieu")
  })

  it('removes the message of the last success when a new attempt starts, so that it does not stay beside an error', async () => {
    let current = received
    let calls = 0
    stubApi({
      '/batches/LOT-0000001': () => ok(current),
      '/batches/LOT-0000001/movements': () => {
        calls += 1
        if (calls > 1) {
          return problem(422, { errorCode: 50301 })
        }
        current = {
          ...received,
          status: 'SORTED',
          quantityKg: 480,
          movements: [
            ...received.movements,
            { movementId: 2, movementType: 'SORTING', stationCode: 'SITE-02', quantityKg: 480, occurredAt: '2026-10-22T09:00:00Z' },
          ],
        }
        return created()
      },
    })
    renderApp('/batches/LOT-0000001')
    await screen.findByText('Roma')

    // First attempt: it works, the message of success is shown.
    fill(STATION, 'SITE-02')
    add()
    expect(await screen.findByText('Mouvement Tri ajouté.')).toBeTruthy()
    await screen.findByText('Trié')

    // Second attempt: the API refuses it. Only the error must stay on the screen.
    fill(STATION, 'SITE-03')
    add()

    expect((await screen.findByRole('alert')).textContent).toContain("Ce mouvement n'est pas l'étape suivante du lot.")
    expect(screen.queryByText('Mouvement Tri ajouté.')).toBeNull()
  })
})
