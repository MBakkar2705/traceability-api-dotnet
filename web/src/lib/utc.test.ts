import { describe, expect, it } from 'vitest'
import { nowUtcInput, toUtcText } from './utc'

describe('toUtcText', () => {
  it('adds the seconds and the Z to the value of a date and time field', () => {
    expect(toUtcText('2026-10-14T06:00')).toBe('2026-10-14T06:00:00Z')
  })

  it('keeps the seconds when the field gives them', () => {
    expect(toUtcText('2026-10-14T06:00:30')).toBe('2026-10-14T06:00:30Z')
  })

  it('leaves an empty value empty, so that the API says the field is required', () => {
    expect(toUtcText('')).toBe('')
  })

  it('leaves anything else as it is, so that the API refuses it and a surprise stays visible', () => {
    expect(toUtcText('tomorrow')).toBe('tomorrow')
  })
})

describe('nowUtcInput', () => {
  it('gives the UTC time in the format of a date and time field', () => {
    expect(nowUtcInput(new Date(Date.UTC(2026, 9, 14, 6, 30, 45, 123)))).toBe('2026-10-14T06:30')
  })

  it('does not depend on the time zone of the machine, even at the turn of the year', () => {
    expect(nowUtcInput(new Date(Date.UTC(2026, 11, 31, 23, 59, 59)))).toBe('2026-12-31T23:59')
  })
})
