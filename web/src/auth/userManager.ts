import { InMemoryWebStorage, UserManager, WebStorageStateStore } from 'oidc-client-ts'
import { AUTH_AUTHORITY, AUTH_CLIENT_ID } from '../config'

let manager: UserManager | null = null

// The object of the library that talks to Keycloak (lot 10c). It is built at the first use and
// not when the file is imported, so the code that never signs in does not build it.
export function getUserManager(): UserManager {
  if (manager === null) {
    manager = new UserManager({
      authority: AUTH_AUTHORITY,
      client_id: AUTH_CLIENT_ID,
      redirect_uri: `${window.location.origin}/auth/callback`,
      post_logout_redirect_uri: `${window.location.origin}/`,
      // Authorization code flow. The library always adds PKCE (method S256) to it.
      response_type: 'code',
      scope: 'openid profile',
      // The user and the tokens stay in memory: nothing is written to a storage of the browser,
      // so a reload of the page signs out (ADR 0014).
      userStore: new WebStorageStateStore({ store: new InMemoryWebStorage() }),
      // The token is renewed before it expires (it lasts 300 seconds).
      automaticSilentRenew: true,
    })
  }
  return manager
}
