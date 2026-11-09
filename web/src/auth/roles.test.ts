import { describe, expect, it } from 'vitest'
import { fakeToken, tokenWithRoles } from '../test/fakeToken'
import { canWrite, readRoles } from './roles'

describe('readRoles', () => {
  it('reads the roles of the realm in the token', () => {
    const token = tokenWithRoles('writer', 'default-roles-traceability', 'offline_access')

    expect(readRoles(token)).toEqual(['writer', 'default-roles-traceability', 'offline_access'])
  })

  it('reads a payload written with the - and _ characters of base64url', () => {
    const token = fakeToken({ realm_access: { roles: ['reader'] }, note: '?????????????????' })

    expect(token.split('.')[1]).toMatch(/[-_]/)
    expect(readRoles(token)).toEqual(['reader'])
  })

  it('keeps only the roles that are text', () => {
    const token = fakeToken({ realm_access: { roles: ['writer', 3, null, { name: 'reader' }] } })

    expect(readRoles(token)).toEqual(['writer'])
  })

  it.each([
    ['a token with no realm_access', fakeToken({ sub: 'x' })],
    ['a realm_access that is not an object', fakeToken({ realm_access: 'writer' })],
    ['roles that are not a list', fakeToken({ realm_access: { roles: 'writer' } })],
    ['a payload that is null', fakeToken(null)],
    ['a payload that is a list', fakeToken([])],
    ['a text with no dot', 'abc'],
    ['a payload that is not base64', 'a.b.c'],
    ['a payload that is not JSON', `a.${btoa('not json')}.c`],
    ['an empty text', ''],
  ])('gives no role for %s', (_name, token) => {
    expect(readRoles(token)).toEqual([])
  })
})

describe('canWrite', () => {
  it('is true for the writer role, with or without other roles', () => {
    expect(canWrite(['writer'])).toBe(true)
    expect(canWrite(['offline_access', 'writer'])).toBe(true)
  })

  it('is false for a reader, for another role and for no role', () => {
    expect(canWrite(['reader'])).toBe(false)
    expect(canWrite(['offline_access'])).toBe(false)
    expect(canWrite([])).toBe(false)
  })
})
