// The roles of the signed-in user, read in the payload of the access token (lot 10c). The
// interface does not check the signature of the token: only the API does, and the API decides
// what is allowed. The roles are read here only to show or hide what the user can or cannot do.

export const WRITER = 'writer'

// The role that corrects movements (lot 12a). A supervisor reads and corrects, and does not write.
export const SUPERVISOR = 'supervisor'

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

// A token is three parts separated by dots; the middle one is JSON written in base64url.
function readPayload(token: string): unknown {
  const part = token.split('.')[1]
  if (part === undefined) {
    return undefined
  }
  const base64 = part.replace(/-/g, '+').replace(/_/g, '/')
  const padded = base64 + '='.repeat((4 - (base64.length % 4)) % 4)
  const bytes = Uint8Array.from(atob(padded), (character) => character.charCodeAt(0))
  return JSON.parse(new TextDecoder().decode(bytes))
}

// Keycloak puts the roles of the realm in realm_access.roles. A token that cannot be read, or
// that has no such list, gives no role.
export function readRoles(accessToken: string): string[] {
  try {
    const payload = readPayload(accessToken)
    if (!isRecord(payload) || !isRecord(payload.realm_access) || !Array.isArray(payload.realm_access.roles)) {
      return []
    }
    return payload.realm_access.roles.filter((role): role is string => typeof role === 'string')
  } catch {
    return []
  }
}

export function canWrite(roles: string[]): boolean {
  return roles.includes(WRITER)
}

// Lot 12a: replacing or cancelling a movement is for the supervisor only (not for the writer).
export function canCorrect(roles: string[]): boolean {
  return roles.includes(SUPERVISOR)
}
