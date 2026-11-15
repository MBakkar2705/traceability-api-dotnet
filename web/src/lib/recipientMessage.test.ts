import { describe, expect, it } from 'vitest'
import { recipientMessage, sheetRecipientMessage } from './recipientMessage'
import type { CorrectionSummary } from './recipientMessage'

const before = { stationCode: 'SITE-03', quantityKg: 470, occurredAt: '2026-10-14T17:05:00Z' }

describe('recipientMessage', () => {
  it('lists only what changed when values are replaced, with the reason', () => {
    const summary: CorrectionSummary = {
      kind: 'REPLACE',
      batchCode: 'LOT-1',
      movementType: 'SHIPMENT',
      before,
      after: { ...before, quantityKg: 460 },
      reasonCode: 'MEASUREMENT_ERROR',
      reasonComment: '',
    }

    const text = recipientMessage(summary)

    expect(text).toContain('le lot LOT-1 (étape « expédition »)')
    expect(text).toContain('- Quantité : 470,00 kg → 460,00 kg')
    expect(text).not.toContain('Station')
    expect(text).not.toContain('Date et heure')
    expect(text).toContain('Motif : Erreur de mesure.')
  })

  it('lists the station and the time when they change', () => {
    const text = recipientMessage({
      kind: 'REPLACE',
      batchCode: 'LOT-1',
      movementType: 'SHIPMENT',
      before,
      after: { stationCode: 'SITE-04', quantityKg: 470, occurredAt: '2026-10-15T08:00:00Z' },
      reasonCode: 'OTHER',
      reasonComment: 'Mauvaise station sur le bon de livraison',
    })

    expect(text).toContain('- Station : SITE-03 → SITE-04')
    expect(text).toContain('- Date et heure : 14/10/2026 17:05:00 UTC → 15/10/2026 08:00:00 UTC')
    expect(text).not.toContain('Quantité')
    expect(text).toContain('Motif : Autre (Mauvaise station sur le bon de livraison).')
  })

  it('does not list a time that only differs by a fraction of a second', () => {
    const text = recipientMessage({
      kind: 'REPLACE',
      batchCode: 'LOT-1',
      movementType: 'SHIPMENT',
      before: { ...before, occurredAt: '2026-10-14T17:05:00.1234567Z' },
      after: { ...before, quantityKg: 460 },
      reasonCode: 'DATA_ENTRY_ERROR',
      reasonComment: '',
    })

    expect(text).not.toContain('Date et heure')
  })

  it('says that the step did not happen when it is cancelled', () => {
    const text = recipientMessage({
      kind: 'CANCEL',
      batchCode: 'LOT-1',
      movementType: 'SHIPMENT',
      before,
      reasonCode: 'OTHER',
      reasonComment: "Le camion n'est pas parti",
    })

    expect(text).toContain("l'étape « expédition » est annulée, elle n'a pas eu lieu.")
    expect(text).not.toContain('Valeurs corrigées')
    expect(text).toContain("Motif : Autre (Le camion n'est pas parti).")
  })

  it('starts with a greeting and ends with a closing line', () => {
    const lines = recipientMessage({
      kind: 'CANCEL',
      batchCode: 'LOT-1',
      movementType: 'SHIPMENT',
      before,
      reasonCode: 'DATA_ENTRY_ERROR',
      reasonComment: '  ',
    }).split('\n')

    expect(lines[0]).toBe('Bonjour,')
    expect(lines.at(-1)).toBe('Cordialement')
  })
})

const sheetBefore = { batchCode: 'LOT-1', farmCode: 'F001', variety: 'Roma', harvestDate: '2026-10-14' }

describe('sheetRecipientMessage (lot 12b)', () => {
  it('lists the corrected values and the reason with its comment', () => {
    const text = sheetRecipientMessage({
      before: sheetBefore,
      after: { ...sheetBefore, variety: 'Cherry', harvestDate: '2026-10-13' },
      reasonCode: 'OTHER',
      reasonComment: 'Fiche recopiée du mauvais bon de livraison',
    })

    expect(text).toContain('la fiche du lot LOT-1.')
    expect(text).toContain('Valeurs corrigées :')
    expect(text).toContain('- Variété : Roma → Cherry')
    expect(text).toContain('- Récolte : 14/10/2026 → 13/10/2026')
    expect(text).not.toContain('Ferme')
    expect(text).toContain('Motif : Autre (Fiche recopiée du mauvais bon de livraison).')
  })

  it('gives the new code only when the code changes', () => {
    const changed = sheetRecipientMessage({
      before: sheetBefore,
      after: { ...sheetBefore, batchCode: 'LOT-2' },
      reasonCode: 'DATA_ENTRY_ERROR',
      reasonComment: '',
    })
    const same = sheetRecipientMessage({
      before: sheetBefore,
      after: { ...sheetBefore, variety: 'Cherry' },
      reasonCode: 'DATA_ENTRY_ERROR',
      reasonComment: '',
    })

    expect(changed).toContain('- Code : LOT-1 → LOT-2')
    expect(changed).toContain('Le lot doit maintenant être désigné par le code LOT-2.')
    expect(same).not.toContain('désigné')
    expect(same).not.toContain('Code :')
  })

  it('does not list any value when nothing changed', () => {
    const text = sheetRecipientMessage({
      before: sheetBefore,
      after: { ...sheetBefore },
      reasonCode: 'DATA_ENTRY_ERROR',
      reasonComment: '',
    })

    expect(text).not.toContain('Valeurs corrigées')
    expect(text).toContain('Motif : Erreur de saisie.')
  })

  it('starts with a greeting and ends with a closing line', () => {
    const lines = sheetRecipientMessage({
      before: sheetBefore,
      after: { ...sheetBefore, farmCode: 'F002' },
      reasonCode: 'DATA_ENTRY_ERROR',
      reasonComment: '  ',
    }).split('\n')

    expect(lines[0]).toBe('Bonjour,')
    expect(lines.at(-1)).toBe('Cordialement')
  })
})
