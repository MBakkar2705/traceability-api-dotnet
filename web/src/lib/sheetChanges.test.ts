import { describe, expect, it } from 'vitest'
import { sheetChanges } from './sheetChanges'

const before = { batchCode: 'LOT-1', farmCode: 'F001', variety: 'Roma', harvestDate: '2026-10-14' }

describe('sheetChanges', () => {
  it('lists only the fields that changed, in the order of the sheet', () => {
    const lines = sheetChanges(before, { ...before, variety: 'Cherry', batchCode: 'LOT-2' })

    expect(lines).toEqual(['Code : LOT-1 → LOT-2', 'Variété : Roma → Cherry'])
  })

  it('lists the four fields when all of them changed, with the harvest day in the French format', () => {
    const after = { batchCode: 'LOT-2', farmCode: 'F002', variety: 'Cherry', harvestDate: '2026-10-13' }

    expect(sheetChanges(before, after)).toEqual([
      'Code : LOT-1 → LOT-2',
      'Ferme : F001 → F002',
      'Variété : Roma → Cherry',
      'Récolte : 14/10/2026 → 13/10/2026',
    ])
  })

  it('lists a change of case only', () => {
    expect(sheetChanges(before, { ...before, batchCode: 'lot-1' })).toEqual(['Code : LOT-1 → lot-1'])
  })

  it('lists nothing when nothing changed', () => {
    expect(sheetChanges(before, { ...before })).toEqual([])
  })
})
