// A token that looks like the one of Keycloak: three parts separated by dots, the middle one being
// the payload in JSON written in base64url. The signature is made up: the interface never checks
// it (only the API does). Only for the tests.
function encode(value: unknown): string {
  return btoa(JSON.stringify(value)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

export function fakeToken(payload: unknown): string {
  return `${encode({ alg: 'none', typ: 'JWT' })}.${encode(payload)}.signature`
}

// The payload of a token of Keycloak with these realm roles.
export function tokenWithRoles(...roles: string[]): string {
  return fakeToken({ iss: 'http://localhost:8180/realms/traceability', realm_access: { roles } })
}
