// @vitest-environment jsdom

import { cleanup, fireEvent, screen, within } from '@testing-library/react'
import { afterEach, describe, expect, it } from 'vitest'
import { created, ok, problem, stubApi } from '../test/helpers'
import { READER, SUPERVISOR, WRITER, renderApp } from '../test/renderApp'

afterEach(cleanup)

// Lot 12a: what the batch page shows about corrections, and the supervisor's form.

// A movement as the API sends it, with no correction.
function mv(movement: {
  movementId: number
  movementType: string
  stationCode: string
  quantityKg: number
  occurredAt: string
  authorName: string
}) {
  return {
    ...movement,
    isCancelled: false,
    correctionCount: 0,
    originalStationCode: movement.stationCode,
    originalQuantityKg: movement.quantityKg,
    originalOccurredAt: movement.occurredAt,
  }
}

const reception = mv({ movementId: 1, movementType: 'RECEPTION', stationCode: 'SITE-01', quantityKg: 500, occurredAt: '2026-10-14T06:30:00Z', authorName: 'writer-test' })
const sorting = mv({ movementId: 2, movementType: 'SORTING', stationCode: 'SITE-02', quantityKg: 480, occurredAt: '2026-10-14T10:05:30Z', authorName: 'writer-test' })
const packing = mv({ movementId: 3, movementType: 'PACKING', stationCode: 'SITE-02', quantityKg: 470, occurredAt: '2026-10-14T13:40:00Z', authorName: 'writer-test' })
const shipment = mv({ movementId: 4, movementType: 'SHIPMENT', stationCode: 'SITE-03', quantityKg: 470, occurredAt: '2026-10-14T17:05:00Z', authorName: 'writer-test' })

const base = { batchCode: 'LOT-0000001', farmCode: 'F001', variety: 'Roma', harvestDate: '2026-10-14' }

// Sorted, nothing corrected.
const sorted = { ...base, quantityKg: 480, status: 'SORTED', corrections: [], movements: [reception, sorting] }

// Shipped, nothing corrected.
const shipped = { ...base, quantityKg: 470, status: 'SHIPPED', corrections: [], movements: [reception, sorting, packing, shipment] }

// Packed: the sorting was corrected (475 instead of 480), the shipment was cancelled.
const withCorrections = {
  ...base,
  quantityKg: 470,
  status: 'PACKED',
  movements: [
    reception,
    { ...sorting, quantityKg: 475, originalQuantityKg: 480, correctionCount: 1 },
    packing,
    { ...shipment, isCancelled: true, correctionCount: 1 },
  ],
  corrections: [
    {
      correctionId: 7, movementId: 2, kind: 'REPLACE', movementType: 'SORTING', stationCode: 'SITE-02',
      quantityKg: 475, occurredAt: '2026-10-14T10:05:30Z', reasonCode: 'MEASUREMENT_ERROR',
      reasonComment: 'Balance mal tarée', authorName: 'supervisor-test', correctedAt: '2026-10-15T09:00:00.1234567Z',
    },
    {
      correctionId: 8, movementId: 4, kind: 'CANCEL', movementType: 'SHIPMENT', stationCode: 'SITE-03',
      quantityKg: 470, occurredAt: '2026-10-14T17:05:00Z', reasonCode: 'OTHER',
      reasonComment: "Le camion n'est pas parti", authorName: 'supervisor-test', correctedAt: '2026-10-15T09:05:00Z',
    },
  ],
}

const URL_BATCH = '/batches/LOT-0000001'

describe('BatchPage, what it shows about corrections', () => {
  it('shows the valid values with the value first entered, and marks a corrected and a cancelled movement', async () => {
    stubApi({ [URL_BATCH]: () => ok(withCorrections) })

    renderApp(URL_BATCH)
    await screen.findByText('Roma')

    const rows = within(screen.getAllByRole('table')[0]).getAllByRole('row')
    expect(rows).toHaveLength(5) // the header, then the four movements
    expect(rows[0].textContent).toContain('État')
    // The corrected movement: the valid quantity, the first one under it, the badge.
    expect(rows[2].textContent).toContain('475,00 kg')
    expect(rows[2].textContent).toContain('saisie : 480,00 kg')
    expect(rows[2].textContent).toContain('Corrigé')
    // A movement with no correction has no badge and no "saisie".
    expect(rows[1].textContent).not.toContain('saisie')
    expect(rows[1].textContent).not.toContain('Corrigé')
    // The cancelled movement stays in the list, struck through, with its badge.
    expect(rows[4].textContent).toContain('Annulé')
    expect(rows[4].querySelector('.line-through')).not.toBeNull()
    expect(rows[3].querySelector('.line-through')).toBeNull()
  })

  it('shows the history of the corrections: kind, new values, reason, comment and author', async () => {
    stubApi({ [URL_BATCH]: () => ok(withCorrections) })

    renderApp(URL_BATCH)
    await screen.findByText('Roma')

    expect(screen.getByRole('heading', { name: 'Corrections' })).toBeTruthy()
    const rows = within(screen.getAllByRole('table')[1]).getAllByRole('row')
    expect(rows).toHaveLength(3)
    expect(rows[0].textContent).toContain('Corrigé par')
    expect(rows[1].textContent).toContain('15/10/2026 09:00:00 UTC')
    expect(rows[1].textContent).toContain('Tri')
    expect(rows[1].textContent).toContain('Valeurs remplacées')
    expect(rows[1].textContent).toContain('SITE-02 · 475,00 kg · 14/10/2026 10:05:30 UTC')
    expect(rows[1].textContent).toContain('Erreur de mesure')
    expect(rows[1].textContent).toContain('Balance mal tarée')
    expect(rows[1].textContent).toContain('supervisor-test')
    expect(rows[2].textContent).toContain('Expédition')
    expect(rows[2].textContent).toContain('Mouvement annulé')
    expect(rows[2].textContent).toContain('—')
    expect(rows[2].textContent).toContain('Autre')
    expect(rows[2].textContent).toContain("Le camion n'est pas parti")
  })

  it('shows no history, and one table only, when nothing was corrected', async () => {
    stubApi({ [URL_BATCH]: () => ok(sorted) })

    renderApp(URL_BATCH)
    await screen.findByText('Roma')

    expect(screen.queryByRole('heading', { name: 'Corrections' })).toBeNull()
    expect(screen.getAllByRole('table')).toHaveLength(1)
  })
})

describe('BatchPage, who sees the correction form', () => {
  it('shows it to a supervisor, and not the form that adds a movement', async () => {
    stubApi({ [URL_BATCH]: () => ok(sorted) })

    renderApp(URL_BATCH, SUPERVISOR)
    await screen.findByText('Roma')

    expect(screen.getByRole('heading', { name: 'Corriger un mouvement' })).toBeTruthy()
    expect(screen.queryByRole('button', { name: 'Ajouter le mouvement' })).toBeNull()
  })

  it.each([
    ['a writer', WRITER],
    ['a reader', READER],
  ])('hides it from %s', async (_name, state) => {
    stubApi({ [URL_BATCH]: () => ok(sorted) })

    renderApp(URL_BATCH, state)
    await screen.findByText('Roma')

    expect(screen.queryByRole('heading', { name: 'Corriger un mouvement' })).toBeNull()
    expect(screen.queryByRole('button', { name: 'Enregistrer la correction' })).toBeNull()
  })
})

describe('BatchPage, correcting a movement', () => {
  const MOVEMENT = 'Mouvement à corriger'
  const ACTION = 'Que faire ?'
  const STATION = 'Code de la station'
  const QUANTITY = 'Quantité (kg)'
  const TIME = 'Date et heure (UTC)'
  const REASON = 'Motif'
  const COMMENT = 'Commentaire (obligatoire pour « Autre »)'

  function fill(label: string, value: string) {
    fireEvent.change(screen.getByLabelText(label), { target: { value } })
  }

  const valueOf = (label: string) => (screen.getByLabelText(label) as HTMLInputElement).value

  const posts = (api: ReturnType<typeof stubApi>) => api.mock.calls.filter(([, init]) => init?.method === 'POST')

  it('proposes the movements that are not cancelled, the last one selected, with its values filled in', async () => {
    stubApi({ [URL_BATCH]: () => ok(withCorrections) })

    renderApp(URL_BATCH, SUPERVISOR)
    await screen.findByText('Roma')

    const options = within(screen.getByLabelText(MOVEMENT)).getAllByRole('option')
    expect(options).toHaveLength(3) // the cancelled shipment is not proposed
    expect(options[2].textContent).toContain('Emballage')
    expect(valueOf(MOVEMENT)).toBe('3')
    expect(valueOf(ACTION)).toBe('replace')
    expect(valueOf(STATION)).toBe('SITE-02')
    expect(valueOf(QUANTITY)).toBe('470')
    expect(valueOf(TIME)).toMatch(/^2026-10-14T13:40(:00)?$/)
    expect(valueOf(REASON)).toBe('DATA_ENTRY_ERROR')
  })

  it('fills in the values of another movement when it is chosen', async () => {
    stubApi({ [URL_BATCH]: () => ok(sorted) })
    renderApp(URL_BATCH, SUPERVISOR)
    await screen.findByText('Roma')

    fill(MOVEMENT, '1')

    expect(valueOf(STATION)).toBe('SITE-01')
    expect(valueOf(QUANTITY)).toBe('500')
    expect(valueOf(TIME)).toMatch(/^2026-10-14T06:30(:00)?$/)
  })

  it('replaces the values with POST, reads the batch again, and says so', async () => {
    let current = sorted
    const api = stubApi({
      [URL_BATCH]: () => ok(current),
      [`${URL_BATCH}/movements/2/replace`]: () => {
        current = {
          ...sorted,
          quantityKg: 475,
          corrections: [withCorrections.corrections[0]],
          movements: [reception, { ...sorting, quantityKg: 475, originalQuantityKg: 480, correctionCount: 1 }],
        } as typeof sorted
        return created()
      },
    })
    renderApp(URL_BATCH, SUPERVISOR)
    await screen.findByText('Roma')

    fill(QUANTITY, '475')
    fill(REASON, 'MEASUREMENT_ERROR')
    fill(COMMENT, 'Balance mal tarée')
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer la correction' }))

    expect(await screen.findByText('Correction enregistrée.')).toBeTruthy()
    // The batch is read again: the history appears.
    expect(await screen.findByRole('heading', { name: 'Corrections' })).toBeTruthy()
    const post = posts(api)[0]
    expect(post[0]).toBe(`https://localhost:7080${URL_BATCH}/movements/2/replace`)
    expect(JSON.parse(String(post[1]?.body))).toEqual({
      stationCode: 'SITE-02',
      quantityKg: 475,
      occurredAt: expect.stringMatching(/^2026-10-14T10:05:30(\.000)?Z$/),
      reasonCode: 'MEASUREMENT_ERROR',
      reasonComment: 'Balance mal tarée',
    })
    // The batch was not shipped: no message for a recipient.
    expect(screen.queryByLabelText('Message au destinataire')).toBeNull()
  })

  it('cancels the movement with POST when the action is to cancel', async () => {
    const api = stubApi({
      [URL_BATCH]: () => ok(sorted),
      [`${URL_BATCH}/movements/2/cancel`]: () => created(),
    })
    renderApp(URL_BATCH, SUPERVISOR)
    await screen.findByText('Roma')

    fill(ACTION, 'cancel')
    expect(screen.queryByLabelText(QUANTITY)).toBeNull()
    fill(REASON, 'OTHER')
    fill(COMMENT, 'Tri saisi sur le mauvais lot')
    fireEvent.click(screen.getByRole('button', { name: 'Annuler le mouvement' }))

    expect(await screen.findByText('Mouvement annulé.')).toBeTruthy()
    const post = posts(api)[0]
    expect(post[0]).toBe(`https://localhost:7080${URL_BATCH}/movements/2/cancel`)
    expect(JSON.parse(String(post[1]?.body))).toEqual({
      reasonCode: 'OTHER',
      reasonComment: 'Tri saisi sur le mauvais lot',
    })
  })

  it('gives a message to forward to the recipient when the batch had been shipped', async () => {
    stubApi({
      [URL_BATCH]: () => ok(shipped),
      [`${URL_BATCH}/movements/4/replace`]: () => created(),
    })
    renderApp(URL_BATCH, SUPERVISOR)
    await screen.findByText('Roma')

    fill(QUANTITY, '460')
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer la correction' }))

    expect(await screen.findByText('Ce lot avait été expédié : prévenez le destinataire.')).toBeTruthy()
    const message = (screen.getByLabelText('Message au destinataire') as HTMLTextAreaElement).value
    expect(message).toContain('le lot LOT-0000001 (étape « expédition »)')
    expect(message).toContain('- Quantité : 470,00 kg → 460,00 kg')
    expect(message).toContain('Motif : Erreur de saisie.')
    expect(screen.getByRole('button', { name: 'Copier le message' })).toBeTruthy()
  })

  it('gives no message for the recipient when the shipment was cancelled before', async () => {
    stubApi({
      [URL_BATCH]: () => ok(withCorrections), // PACKED: its shipment is cancelled
      [`${URL_BATCH}/movements/3/replace`]: () => created(),
    })
    renderApp(URL_BATCH, SUPERVISOR)
    await screen.findByText('Roma')

    fill(QUANTITY, '465')
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer la correction' }))

    expect(await screen.findByText('Correction enregistrée.')).toBeTruthy()
    expect(screen.queryByText('Ce lot avait été expédié : prévenez le destinataire.')).toBeNull()
    expect(screen.queryByLabelText('Message au destinataire')).toBeNull()
  })

  it('also gives the message when the shipment itself is cancelled', async () => {
    stubApi({
      [URL_BATCH]: () => ok(shipped),
      [`${URL_BATCH}/movements/4/cancel`]: () => created(),
    })
    renderApp(URL_BATCH, SUPERVISOR)
    await screen.findByText('Roma')

    fill(ACTION, 'cancel')
    fireEvent.click(screen.getByRole('button', { name: 'Annuler le mouvement' }))

    await screen.findByText('Mouvement annulé.')
    const message = (screen.getByLabelText('Message au destinataire') as HTMLTextAreaElement).value
    expect(message).toContain("l'étape « expédition » est annulée, elle n'a pas eu lieu.")
  })

  it('says in French why the API refused, keeps what was typed, and does not read the batch again', async () => {
    const api = stubApi({
      [URL_BATCH]: () => ok(sorted),
      [`${URL_BATCH}/movements/2/replace`]: () => problem(422, { errorCode: 50304 }),
    })
    renderApp(URL_BATCH, SUPERVISOR)
    await screen.findByText('Roma')

    fill(QUANTITY, '999')
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer la correction' }))

    expect((await screen.findByRole('alert')).textContent).toContain(
      "La quantité ne peut pas dépasser celle de l'étape précédente, ni être inférieure à celle de l'étape suivante.",
    )
    expect(valueOf(QUANTITY)).toBe('999')
    expect(api.mock.calls.filter(([, init]) => init?.method !== 'POST')).toHaveLength(1)
    expect(screen.queryByText('Correction enregistrée.')).toBeNull()
  })

  it('says why a movement cannot be cancelled', async () => {
    stubApi({
      [URL_BATCH]: () => ok(sorted),
      [`${URL_BATCH}/movements/2/cancel`]: () => problem(422, { errorCode: 50306 }),
    })
    renderApp(URL_BATCH, SUPERVISOR)
    await screen.findByText('Roma')

    fill(ACTION, 'cancel')
    fireEvent.click(screen.getByRole('button', { name: 'Annuler le mouvement' }))

    expect((await screen.findByRole('alert')).textContent).toContain(
      "Seul le dernier mouvement valable d'un lot peut être annulé.",
    )
  })

  it('shows the messages of an error of shape under the right fields', async () => {
    stubApi({
      [URL_BATCH]: () => ok(sorted),
      [`${URL_BATCH}/movements/2/replace`]: () =>
        problem(400, { errors: { reasonComment: ['At most 500 characters are allowed.'] } }),
    })
    renderApp(URL_BATCH, SUPERVISOR)
    await screen.findByText('Roma')

    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer la correction' }))

    expect((await screen.findByRole('alert')).textContent).toContain('Certains champs sont invalides.')
    expect(screen.getByLabelText(COMMENT).closest('div')!.textContent).toContain('500 caractères au plus.')
  })
})
