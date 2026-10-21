import { describe, expect, it } from 'vitest'
import { formatDate, formatKg, formatUtc } from './format'

describe('formatUtc', () => {
  it('writes a time of the API in UTC, with the mention UTC', () => {
    expect(formatUtc('2026-10-21T16:35:12Z')).toBe('21/10/2026 16:35:12 UTC')
  })

  it('ignores the fractions of second', () => {
    expect(formatUtc('2026-10-21T16:35:12.1234567Z')).toBe('21/10/2026 16:35:12 UTC')
  })

  it('does not move the day around midnight', () => {
    expect(formatUtc('2026-01-01T00:00:00Z')).toBe('01/01/2026 00:00:00 UTC')
    expect(formatUtc('2026-12-31T23:59:59Z')).toBe('31/12/2026 23:59:59 UTC')
  })

  it('returns a text that is not a UTC time unchanged, so that it stays visible', () => {
    expect(formatUtc('2026-10-21T16:35:12+02:00')).toBe('2026-10-21T16:35:12+02:00')
    expect(formatUtc('not a time')).toBe('not a time')
  })
})

describe('formatDate', () => {
  it('writes a day as day/month/year', () => {
    expect(formatDate('2026-10-14')).toBe('14/10/2026')
  })

  it('returns anything else unchanged', () => {
    expect(formatDate('14 October')).toBe('14 October')
  })
})

describe('formatKg', () => {
  it('uses the French decimal comma and always 2 decimals', () => {
    expect(formatKg(500.5)).toBe('500,50 kg')
    expect(formatKg(0.25)).toBe('0,25 kg')
    expect(formatKg(12)).toBe('12,00 kg')
  })
})
