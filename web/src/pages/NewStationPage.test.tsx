// @vitest-environment jsdom

import { act, cleanup, fireEvent, screen } from '@testing-library/react'
import { afterEach, describe, expect, it } from 'vitest'
import { created, deferred, ok, problem, stubApi, stubFetch } from '../test/helpers'
import { renderApp } from '../test/renderApp'

afterEach(cleanup)

const station = { code: 'ZT-STATION', name: 'Test station' }

function fill(label: string, value: string) {
  fireEvent.change(screen.getByLabelText(label), { target: { value } })
}

function fillTheForm() {
  fill('Code', station.code)
  fill('Nom', station.name)
}

function send() {
  fireEvent.click(screen.getByRole('button', { name: 'Créer la station' }))
}

// The text of a field with its messages (the label, the field and the messages under it).
function fieldText(label: string): string {
  return screen.getByLabelText(label).closest('div')!.textContent
}

describe('NewStationPage', () => {
  it('shows the form with its two fields and a link back to the stations', () => {
    renderApp('/new-station')

    expect(screen.getByRole('heading', { name: 'Nouvelle station' })).toBeTruthy()
    expect(screen.getByLabelText('Code')).toBeTruthy()
    expect(screen.getByLabelText('Nom')).toBeTruthy()
    expect(screen.getByRole('link', { name: /Retour aux stations/ }).getAttribute('href')).toBe('/stations')
  })

  it('sends the station with POST, then opens the page of the new station', async () => {
    const api = stubApi({
      '/stations': () => created(),
      '/stations/ZT-STATION': () => ok({ ...station, capabilities: [] }),
    })
    renderApp('/new-station')

    fillTheForm()
    send()

    expect(await screen.findByRole('heading', { name: 'Station ZT-STATION' })).toBeTruthy()
    expect(await screen.findByText('Aucune fonction déclarée.')).toBeTruthy()
    const [address, init] = api.mock.calls[0]
    expect(address).toBe('https://localhost:7080/stations')
    expect(init?.method).toBe('POST')
    expect(JSON.parse(String(init?.body))).toEqual(station)
  })

  it('says in French that the code is taken, and keeps what was typed', async () => {
    stubApi({ '/stations': () => problem(409, { errorCode: 50201 }) })
    renderApp('/new-station')

    fillTheForm()
    send()

    expect((await screen.findByRole('alert')).textContent).toContain('Une station porte déjà ce code.')
    expect((screen.getByLabelText('Code') as HTMLInputElement).value).toBe('ZT-STATION')
    expect(screen.getByRole('heading', { name: 'Nouvelle station' })).toBeTruthy()
  })

  it('shows the messages of an error of shape under the right fields', async () => {
    const errors = { code: ['The field is required.'], name: ['At most 100 characters are allowed.'] }
    stubApi({ '/stations': () => problem(400, { errors }) })
    renderApp('/new-station')

    fillTheForm()
    send()

    const alert = await screen.findByRole('alert')
    expect(alert.textContent).toContain('Certains champs sont invalides.')
    expect(alert.textContent).not.toContain('Champ obligatoire.')
    expect(fieldText('Code')).toContain('Champ obligatoire.')
    expect(fieldText('Nom')).toContain('100 caractères au plus.')
    expect(fieldText('Code')).not.toContain('100 caractères au plus.')
  })

  it('disables the button while sending, and sends only one request when it is clicked twice', async () => {
    const answer = deferred<Response>()
    // The POST waits for the test; the page of the station, opened afterwards, answers at once.
    const api = stubFetch((address) =>
      address.endsWith('/stations') ? answer.promise : Promise.resolve(ok({ ...station, capabilities: [] })),
    )
    renderApp('/new-station')

    fillTheForm()
    const button = screen.getByRole('button', { name: 'Créer la station' })
    fireEvent.click(button)
    fireEvent.click(button)

    expect(api).toHaveBeenCalledTimes(1)
    expect((screen.getByRole('button', { name: 'Envoi…' }) as HTMLButtonElement).disabled).toBe(true)

    await act(async () => answer.resolve(created()))
    expect(await screen.findByRole('heading', { name: 'Station ZT-STATION' })).toBeTruthy()
  })

  it('says that the station may have been saved when the API does not answer', async () => {
    stubFetch(() => Promise.reject(new TypeError('Failed to fetch')))
    renderApp('/new-station')

    fillTheForm()
    send()

    expect((await screen.findByRole('alert')).textContent).toContain("l'enregistrement a peut-être eu lieu")
  })

  it('opens from the list of stations', async () => {
    stubApi({ '/stations': () => ok({ items: [], totalCount: 0, pageNumber: 1, pageSize: 15 }) })
    renderApp('/stations')

    fireEvent.click(await screen.findByRole('link', { name: 'Nouvelle station' }))

    expect(await screen.findByRole('heading', { name: 'Nouvelle station' })).toBeTruthy()
  })
})
