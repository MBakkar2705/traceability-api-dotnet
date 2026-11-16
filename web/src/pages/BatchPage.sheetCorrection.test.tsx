// @vitest-environment jsdom

import { cleanup, fireEvent, screen, within } from '@testing-library/react'
import { afterEach, describe, expect, it } from 'vitest'
import { created, ok, problem, stubApi } from '../test/helpers'
import { AUDITOR, READER, SUPERVISOR, WRITER, renderApp } from '../test/renderApp'

afterEach(cleanup)

// Lot 12b: what the batch page shows about the corrections of the sheet, who sees the names of the
// authors, and the form with which the supervisor corrects the sheet.

const BASE = 'https://localhost:7080'
const URL_BATCH = '/batches/LOT-0000001'

// The one movement of the batch. authorName is null when the API does not show the names.
function movement(authorName: string | null) {
  return {
    movementId: 1,
    movementType: 'RECEPTION',
    stationCode: 'SITE-01',
    quantityKg: 500,
    occurredAt: '2026-10-14T06:30:00Z',
    authorName,
    isCancelled: false,
    correctionCount: 0,
    originalStationCode: 'SITE-01',
    originalQuantityKg: 500,
    originalOccurredAt: '2026-10-14T06:30:00Z',
  }
}

// A batch as the API sends it; `extra` replaces or adds fields.
function batch(authorName: string | null, extra: Record<string, unknown> = {}) {
  return {
    batchCode: 'LOT-0000001',
    farmCode: 'F001',
    variety: 'Roma',
    harvestDate: '2026-10-14',
    quantityKg: 500,
    status: 'RECEIVED',
    movements: [movement(authorName)],
    corrections: [],
    sheetCorrections: [],
    ...extra,
  }
}

// A correction of the movement (lot 12a), only to have a second history in the page.
function movementCorrection(authorName: string | null) {
  return {
    correctionId: 7,
    movementId: 1,
    kind: 'REPLACE',
    movementType: 'RECEPTION',
    stationCode: 'SITE-01',
    quantityKg: 500,
    occurredAt: '2026-10-14T06:30:00Z',
    reasonCode: 'MEASUREMENT_ERROR',
    reasonComment: '',
    authorName,
    correctedAt: '2026-10-15T09:00:00Z',
  }
}

// A correction of the sheet: the variety was Cherry and became Roma, the harvest was the 15th and
// became the 14th. The code and the farm did not change.
function sheetCorrection(authorName: string | null, extra: Record<string, unknown> = {}) {
  return {
    correctionId: 3,
    oldBatchCode: 'LOT-0000001',
    newBatchCode: 'LOT-0000001',
    oldFarmCode: 'F001',
    newFarmCode: 'F001',
    oldVariety: 'Cherry',
    newVariety: 'Roma',
    oldHarvestDate: '2026-10-15',
    newHarvestDate: '2026-10-14',
    reasonCode: 'OTHER',
    reasonComment: 'Fiche recopiée du mauvais bon',
    authorName,
    correctedAt: '2026-10-16T09:00:00.1234567Z',
    ...extra,
  }
}

describe('BatchPage, the history of the corrections of the sheet', () => {
  it('lists only the fields that changed, with the reason, the comment, the author and the date', async () => {
    stubApi({ [URL_BATCH]: () => ok(batch('writer-test', { sheetCorrections: [sheetCorrection('supervisor-test')] })) })

    renderApp(URL_BATCH, AUDITOR)
    await screen.findByText('Roma')

    expect(screen.getByRole('heading', { name: 'Corrections de la fiche' })).toBeTruthy()
    const rows = within(screen.getAllByRole('table')[1]).getAllByRole('row')
    expect(rows).toHaveLength(2)
    expect(rows[0].textContent).toContain('Modifications')
    expect(rows[1].textContent).toContain('16/10/2026 09:00:00 UTC')
    expect(rows[1].textContent).toContain('Variété : Cherry → Roma')
    expect(rows[1].textContent).toContain('Récolte : 15/10/2026 → 14/10/2026')
    expect(rows[1].textContent).not.toContain('Ferme')
    expect(rows[1].textContent).not.toContain('Code :')
    expect(rows[1].textContent).toContain('Autre')
    expect(rows[1].textContent).toContain('Fiche recopiée du mauvais bon')
    expect(rows[1].textContent).toContain('supervisor-test')
  })

  it('shows no history, and one table only, when the sheet was never corrected', async () => {
    stubApi({ [URL_BATCH]: () => ok(batch('writer-test')) })

    renderApp(URL_BATCH, AUDITOR)
    await screen.findByText('Roma')

    expect(screen.queryByRole('heading', { name: 'Corrections de la fiche' })).toBeNull()
    expect(screen.getAllByRole('table')).toHaveLength(1)
  })
})

describe('BatchPage, the names of the authors', () => {
  const everything = (name: string | null) =>
    batch(name, { corrections: [movementCorrection(name)], sheetCorrections: [sheetCorrection(name)] })

  it('leaves out the columns of the authors when the API sends no name', async () => {
    stubApi({ [URL_BATCH]: () => ok(everything(null)) })

    renderApp(URL_BATCH, READER)
    await screen.findByText('Roma')

    const tables = screen.getAllByRole('table')
    expect(tables).toHaveLength(3) // the movements, their corrections, the corrections of the sheet
    for (const table of tables) {
      expect(table.textContent).not.toContain('Auteur')
      expect(table.textContent).not.toContain('Corrigé par')
    }
    // The rest of the histories is still there.
    expect(tables[1].textContent).toContain('Erreur de mesure')
    expect(tables[2].textContent).toContain('Variété : Cherry → Roma')
  })

  it('shows the columns and the names to an auditor, who sees no form', async () => {
    stubApi({ [URL_BATCH]: () => ok(everything('writer-test')) })

    renderApp(URL_BATCH, AUDITOR)
    await screen.findByText('Roma')

    const tables = screen.getAllByRole('table')
    expect(tables[0].textContent).toContain('Auteur')
    expect(tables[0].textContent).toContain('writer-test')
    expect(tables[1].textContent).toContain('Corrigé par')
    expect(tables[2].textContent).toContain('Corrigé par')
    expect(tables[2].textContent).toContain('writer-test')
    expect(screen.queryByRole('heading', { name: 'Ajouter un mouvement' })).toBeNull()
    expect(screen.queryByRole('heading', { name: 'Corriger un mouvement' })).toBeNull()
    expect(screen.queryByRole('heading', { name: 'Corriger la fiche' })).toBeNull()
  })
})

const CODE = 'Code du lot'
const FARM = 'Code de la ferme'
const VARIETY = 'Variété'
const HARVEST = 'Date de récolte'
const REASON = 'Motif'
const COMMENT = 'Commentaire (obligatoire pour « Autre »)'

// The supervisor also sees the form that corrects a movement, which has fields with the same names
// (the reason, the comment): the fields are searched in the form of the sheet only.
const sheetForm = () => screen.getByLabelText(CODE).closest('form')!
const field = (label: string) => within(sheetForm()).getByLabelText(label) as HTMLInputElement
const fill = (label: string, value: string) => fireEvent.change(field(label), { target: { value } })
const send = () => fireEvent.click(within(sheetForm()).getByRole('button', { name: 'Corriger la fiche' }))
const posts = (api: ReturnType<typeof stubApi>) => api.mock.calls.filter(([, init]) => init?.method === 'POST')
const reads = (api: ReturnType<typeof stubApi>) => api.mock.calls.filter(([, init]) => init?.method !== 'POST')

describe('BatchPage, who sees the form that corrects the sheet', () => {
  it('shows it to a supervisor, with the values of the sheet filled in and two reasons only', async () => {
    stubApi({ [URL_BATCH]: () => ok(batch('writer-test')) })

    renderApp(URL_BATCH, SUPERVISOR)
    await screen.findByText('Roma')

    expect(screen.getByRole('heading', { name: 'Corriger la fiche' })).toBeTruthy()
    expect(field(CODE).value).toBe('LOT-0000001')
    expect(field(FARM).value).toBe('F001')
    expect(field(VARIETY).value).toBe('Roma')
    expect(field(HARVEST).value).toBe('2026-10-14')
    expect(field(REASON).value).toBe('DATA_ENTRY_ERROR')
    const reasons = within(field(REASON)).getAllByRole('option').map((option) => (option as HTMLOptionElement).value)
    expect(reasons).toEqual(['DATA_ENTRY_ERROR', 'OTHER'])
  })

  it.each([
    ['a writer', WRITER],
    ['a reader', READER],
    ['an auditor', AUDITOR],
  ])('hides it from %s', async (_name, state) => {
    stubApi({ [URL_BATCH]: () => ok(batch(null)) })

    renderApp(URL_BATCH, state)
    await screen.findByText('Roma')

    expect(screen.queryByRole('heading', { name: 'Corriger la fiche' })).toBeNull()
    expect(screen.queryByRole('button', { name: 'Corriger la fiche' })).toBeNull()
  })
})

describe('BatchPage, correcting the sheet', () => {
  it('sends the correction with POST, reads the batch again, says so, and starts the form again', async () => {
    let current = batch('writer-test')
    const api = stubApi({
      [URL_BATCH]: () => ok(current),
      [`${URL_BATCH}/correct`]: () => {
        current = batch('supervisor-test', {
          variety: 'Cherry',
          sheetCorrections: [sheetCorrection('supervisor-test', { oldVariety: 'Roma', newVariety: 'Cherry', oldHarvestDate: '2026-10-14' })],
        })
        return created()
      },
    })
    renderApp(URL_BATCH, SUPERVISOR)
    await screen.findByText('Roma')

    fill(VARIETY, 'Cherry')
    fill(COMMENT, 'Variété mal saisie')
    send()

    expect(await screen.findByText('Fiche corrigée.')).toBeTruthy()
    // The batch is read again: the history appears, and the form starts again (the comment is empty).
    expect(await screen.findByRole('heading', { name: 'Corrections de la fiche' })).toBeTruthy()
    expect(field(COMMENT).value).toBe('')
    expect(field(VARIETY).value).toBe('Cherry')
    const post = posts(api)[0]
    expect(post[0]).toBe(`${BASE}${URL_BATCH}/correct`)
    expect(JSON.parse(String(post[1]?.body))).toEqual({
      newBatchCode: 'LOT-0000001',
      farmCode: 'F001',
      variety: 'Cherry',
      harvestDate: '2026-10-14',
      reasonCode: 'DATA_ENTRY_ERROR',
      reasonComment: 'Variété mal saisie',
    })
    // The batch was not shipped: no message for a recipient.
    expect(screen.queryByLabelText('Message au destinataire')).toBeNull()
  })

  it('opens the batch under its new code when the code changed, and keeps the message of success', async () => {
    const api = stubApi({
      [URL_BATCH]: () => ok(batch('x')),
      [`${URL_BATCH}/correct`]: () => created(),
      '/batches/LOT-0000002': () =>
        ok(
          batch('x', {
            batchCode: 'LOT-0000002',
            sheetCorrections: [sheetCorrection('x', { oldBatchCode: 'LOT-0000001', newBatchCode: 'LOT-0000002' })],
          }),
        ),
    })
    renderApp(URL_BATCH, SUPERVISOR)
    await screen.findByText('Roma')

    fill(CODE, 'LOT-0000002')
    send()

    expect(await screen.findByText('Fiche corrigée.')).toBeTruthy()
    expect(screen.getByRole('heading', { name: 'Lot LOT-0000002' })).toBeTruthy()
    expect(api.mock.calls.map(([address]) => address)).toContain(`${BASE}/batches/LOT-0000002`)
    // The form now works on the new code.
    expect(field(CODE).value).toBe('LOT-0000002')
  })

  it('gives a message to forward to the recipient when the batch had been shipped, with the new code', async () => {
    stubApi({
      [URL_BATCH]: () => ok(batch('x', { status: 'SHIPPED' })),
      [`${URL_BATCH}/correct`]: () => created(),
      '/batches/LOT-0000002': () => ok(batch('x', { status: 'SHIPPED', batchCode: 'LOT-0000002' })),
    })
    renderApp(URL_BATCH, SUPERVISOR)
    await screen.findByText('Roma')

    fill(CODE, 'LOT-0000002')
    send()

    expect(await screen.findByText('Ce lot avait été expédié : prévenez le destinataire.')).toBeTruthy()
    const message = (screen.getByLabelText('Message au destinataire') as HTMLTextAreaElement).value
    expect(message).toContain('la fiche du lot LOT-0000001.')
    expect(message).toContain('- Code : LOT-0000001 → LOT-0000002')
    expect(message).toContain('Le lot doit maintenant être désigné par le code LOT-0000002.')
    expect(message).toContain('Motif : Erreur de saisie.')
  })

  it('gives the message without a new code when the code did not change', async () => {
    stubApi({
      [URL_BATCH]: () => ok(batch('x', { status: 'SHIPPED' })),
      [`${URL_BATCH}/correct`]: () => created(),
    })
    renderApp(URL_BATCH, SUPERVISOR)
    await screen.findByText('Roma')

    fill(VARIETY, 'Cherry')
    send()

    await screen.findByText('Ce lot avait été expédié : prévenez le destinataire.')
    const message = (screen.getByLabelText('Message au destinataire') as HTMLTextAreaElement).value
    expect(message).toContain('- Variété : Roma → Cherry')
    expect(message).not.toContain('Code :')
    expect(message).not.toContain('désigné')
  })

  it.each([
    [409, 50203, "Ce code est l'ancien code d'un autre lot."],
    [409, 50202, 'Un lot porte déjà ce code.'],
    [422, 50308, 'Les nouvelles valeurs sont identiques aux valeurs actuelles : rien à corriger.'],
    [422, 50309, 'La date de récolte ne peut pas être après le jour de la réception.'],
    [404, 50101, 'Ferme introuvable.'],
  ])('says in French why the API refused (%i / %i), keeps what was typed, and does not read again', async (status, errorCode, text) => {
    const api = stubApi({
      [URL_BATCH]: () => ok(batch('x')),
      [`${URL_BATCH}/correct`]: () => problem(status, { errorCode }),
    })
    renderApp(URL_BATCH, SUPERVISOR)
    await screen.findByText('Roma')

    fill(CODE, 'LOT-0000009')
    send()

    expect((await screen.findByRole('alert')).textContent).toContain(text)
    expect(field(CODE).value).toBe('LOT-0000009')
    expect(reads(api)).toHaveLength(1)
    expect(screen.queryByText('Fiche corrigée.')).toBeNull()
  })

  it('shows the messages of an error of shape under the right field', async () => {
    stubApi({
      [URL_BATCH]: () => ok(batch('x')),
      [`${URL_BATCH}/correct`]: () => problem(400, { errors: { newBatchCode: ['The field is required.'] } }),
    })
    renderApp(URL_BATCH, SUPERVISOR)
    await screen.findByText('Roma')

    send()

    expect((await screen.findByRole('alert')).textContent).toContain('Certains champs sont invalides.')
    expect(field(CODE).closest('div')!.textContent).toContain('Champ obligatoire.')
  })
})

describe('BatchPage, an old code in the address', () => {
  it('replaces it by the current code, and writes with the current code', async () => {
    const api = stubApi({
      // The API finds the batch by its old code, and its answer carries the current code.
      '/batches/LOT-OLD': () => ok(batch('x')),
      [URL_BATCH]: () => ok(batch('x')),
      [`${URL_BATCH}/correct`]: () => created(),
    })

    renderApp('/batches/LOT-OLD', SUPERVISOR)

    expect(await screen.findByRole('heading', { name: 'Lot LOT-0000001' })).toBeTruthy()
    await screen.findByText('Roma')
    expect(api.mock.calls[0][0]).toBe(`${BASE}/batches/LOT-OLD`)

    fill(VARIETY, 'Cherry')
    send()

    expect(await screen.findByText('Fiche corrigée.')).toBeTruthy()
    // Written with the current code: with the old one the API would refuse (50104).
    expect(posts(api)[0][0]).toBe(`${BASE}${URL_BATCH}/correct`)
  })
})
