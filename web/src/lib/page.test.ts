import { describe, expect, it } from 'vitest'
import { readPageNumber } from './page'

describe('readPageNumber', () => {
  it('reads a whole number from 1', () => {
    expect(readPageNumber('1')).toBe(1)
    expect(readPageNumber('42')).toBe(42)
  })

  it.each([null, '', 'abc', '0', '-3', '2.5', '1e3', ' 2', '99999999999999999999'])('means page 1 for %j', (value) => {
    expect(readPageNumber(value)).toBe(1)
  })
})
