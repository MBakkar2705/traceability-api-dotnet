import { describe, expect, it } from 'vitest'
import { movementLabel, statusLabel } from './labels'

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
})
