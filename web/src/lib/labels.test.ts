import { describe, expect, it } from 'vitest'
import { authorLabel, correctionKindLabel, movementLabel, reasonLabel, statusLabel } from './labels'

describe('labels', () => {
  it('writes the statuses in French', () => {
    expect(['RECEIVED', 'SORTED', 'PACKED', 'SHIPPED'].map(statusLabel)).toEqual(['Reçu', 'Trié', 'Emballé', 'Expédié'])
  })

  it('writes the movement types in French', () => {
    expect(['RECEPTION', 'SORTING', 'PACKING', 'SHIPMENT'].map(movementLabel)).toEqual([
      'Réception',
      'Tri',
      'Emballage',
      'Expédition',
    ])
  })

  it('shows a value it does not know as it is', () => {
    expect(statusLabel('LOST')).toBe('LOST')
    expect(movementLabel('RETURN')).toBe('RETURN')
  })

  it('does not take the name of an object method for a label', () => {
    expect(statusLabel('constructor')).toBe('constructor')
  })

  it('writes the author of the first data in French and shows any other user name as it is', () => {
    expect(authorLabel('Initial_User')).toBe('Données initiales')
    expect(authorLabel('writer-test')).toBe('writer-test')
    expect(authorLabel('constructor')).toBe('constructor')
  })

  it('writes the reasons and the kinds of correction in French, and shows an unknown one as it is', () => {
    expect(['DATA_ENTRY_ERROR', 'MEASUREMENT_ERROR', 'OTHER'].map(reasonLabel)).toEqual([
      'Erreur de saisie',
      'Erreur de mesure',
      'Autre',
    ])
    expect(['REPLACE', 'CANCEL'].map(correctionKindLabel)).toEqual(['Valeurs remplacées', 'Mouvement annulé'])
    expect(reasonLabel('BECAUSE')).toBe('BECAUSE')
    expect(correctionKindLabel('constructor')).toBe('constructor')
  })
})
