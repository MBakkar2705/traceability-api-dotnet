// @vitest-environment jsdom

import { act, cleanup, fireEvent, screen } from '@testing-library/react'
import { afterEach, describe, expect, it } from 'vitest'
import { created, deferred, ok, problem, stubApi, stubFetch } from '../test/helpers'
import { renderApp } from '../test/renderApp'

afterEach(cleanup)

// What is typed in the form, and what the API must receive for it.
const typed = {
  'Code du lot': 'ZT-LOT',
  'Code de la ferme': 'ZT-FARM',
  'Variété': 'Roma',
  'Date de récolte': '2026-10-20',
  'Quantité (kg)': '125.5',
  'Code de la station': 'ZT-STATION',
  'Date et heure de réception (UTC)': '2026-10-22T08:30',
}

const sent = {
  batchCode: 'ZT-LOT',
  farmCode: 'ZT-FARM',
  variety: 'Roma',
  harvestDate: '2026-10-20',
  quantityKg: 125.5,
  stationCode: 'ZT-STATION',
  occurredAt: '2026-10-22T08:30:00Z',
}

// The batch as the API shows it once it is created.
const batch = {
  batchCode: 'ZT-LOT',
  farmCode: 'ZT-FARM',
  variety: 'Roma',
  harvestDate: '2026-10-20',
  quantityKg: 125.5,
  status: 'RECEIVED',
  movements: [
    { movementId: 1, movementType: 'RECEPTION', stationCode: 'ZT-STATION', quantityKg: 125.5, occurredAt: '2026-10-22T08:30:00Z' },
  ],
}

function fill(label: string, value: string) {
  fireEvent.change(screen.getByLabelText(label), { target: { value } })
}

function fillTheForm() {
  for (const [label, value] of Object.entries(typed)) {
    fill(label, value)
  }
}

function send() {
  fireEvent.click(screen.getByRole('button', { name: 'Créer le lot' }))
}

// The text of a field with its messages (the label, the field and the messages under it).
function fieldText(label: string): string {
  return screen.getByLabelText(label).closest('div')!.textContent
}

describe('NewBatchPage', () => {
  it('shows the form with its seven fields, the time already filled in, and a link back to the batches', () => {
    renderApp('/new-batch')

    expect(screen.getByRole('heading', { name: 'Nouveau lot' })).toBeTruthy()
    for (const label of Object.keys(typed)) {
      expect(screen.getByLabelText(label)).toBeTruthy()
    }
    // The current time in UTC, without seconds: the user only changes it if the reception was earlier.
    expect((screen.getByLabelText('Date et heure de réception (UTC)') as HTMLInputElement).value).toMatch(
      /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/,
    )
    expect(screen.getByRole('link', { name: /Retour aux lots/ }).getAttribute('href')).toBe('/batches')
  })

  it('sends the batch with POST, then opens the page of the new batch', async () => {
    const api = stubApi({
      '/batches': () => created(),
      '/batches/ZT-LOT': () => ok(batch),
    })
    renderApp('/new-batch')

    fillTheForm()
    send()

    expect(await screen.findByRole('heading', { name: 'Lot ZT-LOT' })).toBeTruthy()
    const [address, init] = api.mock.calls[0]
    expect(address).toBe('https://localhost:7080/batches')
    expect(init?.method).toBe('POST')
    // The quantity is a number, not a text.
    expect(JSON.parse(String(init?.body))).toEqual(sent)
  })

  it('writes the time typed in UTC with a Z at the end', async () => {
    const api = stubApi({ '/batches': () => problem(409, { errorCode: 50202 }) })
    renderApp('/new-batch')

    fillTheForm()
    fill('Date et heure de réception (UTC)', '2026-12-31T23:59')
    send()

    await screen.findByRole('alert')
    expect(JSON.parse(String(api.mock.calls[0][1]?.body)).occurredAt).toBe('2026-12-31T23:59:00Z')
  })

  it('says in French that the code is taken, and keeps what was typed', async () => {
    stubApi({ '/batches': () => problem(409, { errorCode: 50202 }) })
    renderApp('/new-batch')

    fillTheForm()
    send()

    expect((await screen.findByRole('alert')).textContent).toContain('Un lot porte déjà ce code.')
    expect((screen.getByLabelText('Code du lot') as HTMLInputElement).value).toBe('ZT-LOT')
    expect((screen.getByLabelText('Quantité (kg)') as HTMLInputElement).value).toBe('125.5')
    expect(screen.getByRole('heading', { name: 'Nouveau lot' })).toBeTruthy()
  })

  it('shows the messages of an error of shape under the right fields', async () => {
    const errors = {
      batchCode: ['The field is required.'],
      variety: ['At most 100 characters are allowed.'],
      quantityKg: ['The field is required.'],
    }
    stubApi({ '/batches': () => problem(400, { errors }) })
    renderApp('/new-batch')

    fillTheForm()
    send()

    const alert = await screen.findByRole('alert')
    expect(alert.textContent).toContain('Certains champs sont invalides.')
    expect(alert.textContent).not.toContain('Champ obligatoire.')
    expect(fieldText('Code du lot')).toContain('Champ obligatoire.')
    expect(fieldText('Variété')).toContain('100 caractères au plus.')
    expect(fieldText('Quantité (kg)')).toContain('Champ obligatoire.')
    expect(fieldText('Code de la ferme')).not.toContain('Champ obligatoire.')
  })

  it('disables the button while sending, and sends only one request when it is clicked twice', async () => {
    const answer = deferred<Response>()
    // The POST waits for the test; the page of the batch, opened afterwards, answers at once.
    const api = stubFetch((address) =>
      address.endsWith('/batches') ? answer.promise : Promise.resolve(ok(batch)),
    )
    renderApp('/new-batch')

    fillTheForm()
    const button = screen.getByRole('button', { name: 'Créer le lot' })
    fireEvent.click(button)
    fireEvent.click(button)

    expect(api).toHaveBeenCalledTimes(1)
    expect((screen.getByRole('button', { name: 'Envoi…' }) as HTMLButtonElement).disabled).toBe(true)

    await act(async () => answer.resolve(created()))
    expect(await screen.findByRole('heading', { name: 'Lot ZT-LOT' })).toBeTruthy()
  })

  it('says that the batch may have been saved when the API does not answer', async () => {
    stubFetch(() => Promise.reject(new TypeError('Failed to fetch')))
    renderApp('/new-batch')

    fillTheForm()
    send()

    expect((await screen.findByRole('alert')).textContent).toContain("l'enregistrement a peut-être eu lieu")
  })

  it('opens from the list of batches', async () => {
    stubApi({ '/batches': () => ok({ items: [], totalCount: 0, pageNumber: 1, pageSize: 15 }) })
    renderApp('/batches')

    fireEvent.click(await screen.findByRole('link', { name: 'Nouveau lot' }))

    expect(await screen.findByRole('heading', { name: 'Nouveau lot' })).toBeTruthy()
  })
})
