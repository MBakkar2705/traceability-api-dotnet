// @vitest-environment jsdom

import { act, cleanup, fireEvent, screen } from '@testing-library/react'
import { afterEach, describe, expect, it } from 'vitest'
import { created, deferred, ok, problem, stubApi, stubFetch } from '../test/helpers'
import { renderApp } from '../test/renderApp'

afterEach(cleanup)

const farm = { code: 'ZT-FARM', name: 'Test farm', region: 'Region A' }

function fill(label: string, value: string) {
  fireEvent.change(screen.getByLabelText(label), { target: { value } })
}

function fillTheForm() {
  fill('Code', farm.code)
  fill('Nom', farm.name)
  fill('Région', farm.region)
}

function send() {
  fireEvent.click(screen.getByRole('button', { name: 'Créer la ferme' }))
}

// The text of a field with its messages (the label, the field and the messages under it).
function fieldText(label: string): string {
  return screen.getByLabelText(label).closest('div')!.textContent
}

describe('NewFarmPage', () => {
  it('shows the form with its three fields and a link back to the farms', () => {
    renderApp('/new-farm')

    expect(screen.getByRole('heading', { name: 'Nouvelle ferme' })).toBeTruthy()
    expect(screen.getByLabelText('Code')).toBeTruthy()
    expect(screen.getByLabelText('Nom')).toBeTruthy()
    expect(screen.getByLabelText('Région')).toBeTruthy()
    expect(screen.getByRole('link', { name: /Retour aux fermes/ }).getAttribute('href')).toBe('/farms')
  })

  it('sends the farm with POST, then says it is created and empties the form', async () => {
    const api = stubApi({ '/farms': () => created(farm) })
    renderApp('/new-farm')

    fillTheForm()
    send()

    expect((await screen.findByRole('status')).textContent).toContain('Ferme ZT-FARM créée.')
    const [address, init] = api.mock.calls[0]
    expect(address).toBe('https://localhost:7080/farms')
    expect(init?.method).toBe('POST')
    expect(JSON.parse(String(init?.body))).toEqual(farm)
    expect((screen.getByLabelText('Code') as HTMLInputElement).value).toBe('')
    expect(screen.getByRole('link', { name: 'Voir les fermes' }).getAttribute('href')).toBe('/farms')
  })

  it('says in French that the code is taken, and keeps what was typed', async () => {
    stubApi({ '/farms': () => problem(409, { errorCode: 50200 }) })
    renderApp('/new-farm')

    fillTheForm()
    send()

    expect((await screen.findByRole('alert')).textContent).toContain('Une ferme porte déjà ce code.')
    expect((screen.getByLabelText('Code') as HTMLInputElement).value).toBe('ZT-FARM')
    expect(screen.queryByRole('status')).toBeNull()
  })

  it('shows the messages of an error of shape under the right fields', async () => {
    const errors = { code: ['The field is required.'], name: ['At most 100 characters are allowed.'] }
    stubApi({ '/farms': () => problem(400, { errors }) })
    renderApp('/new-farm')

    fillTheForm()
    send()

    const alert = await screen.findByRole('alert')
    expect(alert.textContent).toContain('Certains champs sont invalides.')
    expect(alert.textContent).not.toContain('Champ obligatoire.')
    expect(fieldText('Code')).toContain('Champ obligatoire.')
    expect(fieldText('Nom')).toContain('100 caractères au plus.')
    expect(fieldText('Région')).not.toContain('Champ obligatoire.')
  })

  it('disables the button while sending, and sends only one request when it is clicked twice', async () => {
    const answer = deferred<Response>()
    const api = stubFetch(() => answer.promise)
    renderApp('/new-farm')

    fillTheForm()
    const button = screen.getByRole('button', { name: 'Créer la ferme' })
    fireEvent.click(button)
    fireEvent.click(button)

    expect(api).toHaveBeenCalledTimes(1)
    expect((screen.getByRole('button', { name: 'Envoi…' }) as HTMLButtonElement).disabled).toBe(true)

    await act(async () => answer.resolve(created(farm)))
    expect((await screen.findByRole('status')).textContent).toContain('créée')
  })

  it('says that the farm may have been saved when the API does not answer', async () => {
    stubFetch(() => Promise.reject(new TypeError('Failed to fetch')))
    renderApp('/new-farm')

    fillTheForm()
    send()

    expect((await screen.findByRole('alert')).textContent).toContain("l'enregistrement a peut-être eu lieu")
  })

  it('opens from the list of farms', async () => {
    stubApi({ '/farms': () => ok({ items: [], totalCount: 0, pageNumber: 1, pageSize: 15 }) })
    renderApp('/farms')

    fireEvent.click(await screen.findByRole('link', { name: 'Nouvelle ferme' }))

    expect(await screen.findByRole('heading', { name: 'Nouvelle ferme' })).toBeTruthy()
  })
})
