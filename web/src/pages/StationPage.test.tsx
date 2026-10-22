// @vitest-environment jsdom

import { act, cleanup, fireEvent, screen } from '@testing-library/react'
import { afterEach, describe, expect, it } from 'vitest'
import { created, deferred, ok, problem, stubApi, stubFetch } from '../test/helpers'
import { renderApp } from '../test/renderApp'

afterEach(cleanup)

const station = { code: 'SITE-01', name: 'Reception site 1', capabilities: ['RECEPTION', 'SORTING'] }

describe('StationPage', () => {
  it('shows the station with its functions in French', async () => {
    stubApi({ '/stations/SITE-01': () => ok(station) })

    renderApp('/stations/SITE-01')

    expect(await screen.findByText('Reception site 1')).toBeTruthy()
    expect(screen.getByRole('heading', { name: 'Station SITE-01' })).toBeTruthy()
    // The functions of the station are in <span>s: the form has the same words in its list.
    expect(screen.getByText('Réception', { selector: 'span' })).toBeTruthy()
    expect(screen.getByText('Tri', { selector: 'span' })).toBeTruthy()
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
    expect(await screen.findByText('Réception', { selector: 'span' })).toBeTruthy()
  })
})

describe('StationPage, adding a function', () => {
  const FIELD_LABEL = 'Fonction à ajouter'

  function add() {
    fireEvent.click(screen.getByRole('button', { name: 'Ajouter la fonction' }))
  }

  // The requests that are not the POST: the reads of the station.
  const reads = (api: ReturnType<typeof stubFetch>) => api.mock.calls.filter(([, init]) => init?.method !== 'POST')

  it('offers the four functions in French, each with the movement type of the API', async () => {
    stubApi({ '/stations/SITE-01': () => ok(station) })

    renderApp('/stations/SITE-01')
    await screen.findByText('Reception site 1')

    expect(screen.getByLabelText(FIELD_LABEL)).toBeTruthy()
    const options = screen.getAllByRole('option').map((option) => [option.textContent, (option as HTMLOptionElement).value])
    expect(options).toEqual([
      ['Réception', 'RECEPTION'],
      ['Tri', 'SORTING'],
      ['Emballage', 'PACKING'],
      ['Expédition', 'SHIPMENT'],
    ])
  })

  it('adds a function with POST, then reads the station again and says that it is added', async () => {
    let added = false
    const api = stubApi({
      '/stations/SITE-01': () => ok({ ...station, capabilities: added ? [...station.capabilities, 'PACKING'] : station.capabilities }),
      '/stations/SITE-01/capabilities': () => {
        added = true
        return created()
      },
    })
    renderApp('/stations/SITE-01')
    await screen.findByText('Reception site 1')

    fireEvent.change(screen.getByLabelText(FIELD_LABEL), { target: { value: 'PACKING' } })
    add()

    expect(await screen.findByText('Fonction Emballage ajoutée.')).toBeTruthy()
    // The station is read again: the new function is among the functions of the station.
    expect(await screen.findByText('Emballage', { selector: 'span' })).toBeTruthy()
    const post = api.mock.calls.find(([, init]) => init?.method === 'POST')!
    expect(post[0]).toBe('https://localhost:7080/stations/SITE-01/capabilities')
    expect(JSON.parse(String(post[1]?.body))).toEqual({ movementType: 'PACKING' })
    expect(reads(api)).toHaveLength(2)
  })

  it('says in French that the station already has the function, and does not read the station again', async () => {
    const api = stubApi({
      '/stations/SITE-01': () => ok(station),
      '/stations/SITE-01/capabilities': () => problem(409, { errorCode: 50203 }),
    })
    renderApp('/stations/SITE-01')
    await screen.findByText('Reception site 1')

    add()

    expect((await screen.findByRole('alert')).textContent).toContain('Cette station a déjà cette fonction.')
    expect(reads(api)).toHaveLength(1)
  })

  it('disables the button while sending, and sends only one request when it is clicked twice', async () => {
    const answer = deferred<Response>()
    const api = stubFetch((address) =>
      address.endsWith('/capabilities') ? answer.promise : Promise.resolve(ok(station)),
    )
    renderApp('/stations/SITE-01')
    await screen.findByText('Reception site 1')

    const button = screen.getByRole('button', { name: 'Ajouter la fonction' })
    fireEvent.click(button)
    fireEvent.click(button)

    expect(api.mock.calls.filter(([, init]) => init?.method === 'POST')).toHaveLength(1)
    expect((screen.getByRole('button', { name: 'Envoi…' }) as HTMLButtonElement).disabled).toBe(true)

    await act(async () => answer.resolve(created()))
    expect(await screen.findByText('Fonction Réception ajoutée.')).toBeTruthy()
  })

  it('says that the function may have been added when the API does not answer', async () => {
    stubFetch((address) =>
      address.endsWith('/capabilities') ? Promise.reject(new TypeError('Failed to fetch')) : Promise.resolve(ok(station)),
    )
    renderApp('/stations/SITE-01')
    await screen.findByText('Reception site 1')

    add()

    expect((await screen.findByRole('alert')).textContent).toContain("l'enregistrement a peut-être eu lieu")
  })

  it('has no form when the station does not exist', async () => {
    stubApi({ '/stations/SITE-99': () => problem(404, { errorCode: 50102 }) })

    renderApp('/stations/SITE-99')

    expect((await screen.findByRole('alert')).textContent).toContain('Station introuvable.')
    expect(screen.queryByLabelText(FIELD_LABEL)).toBeNull()
    expect(screen.queryByRole('button', { name: 'Ajouter la fonction' })).toBeNull()
  })
})
