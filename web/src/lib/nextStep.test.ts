import { describe, expect, it } from 'vitest'
import { nextMovementType } from './nextStep'

describe('nextMovementType', () => {
  it.each([
    ['RECEIVED', 'SORTING'],
    ['SORTED', 'PACKING'],
    ['PACKED', 'SHIPMENT'],
  ])('is the step after the status %s: %s', (status, next) => {
    expect(nextMovementType(status)).toBe(next)
  })

  it('gives nothing after SHIPPED: the batch accepts no more movement', () => {
    expect(nextMovementType('SHIPPED')).toBeUndefined()
  })
})
