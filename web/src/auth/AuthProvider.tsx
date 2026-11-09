import { useEffect, useMemo, useState } from 'react'
import type { ReactNode } from 'react'
import type { User } from 'oidc-client-ts'
import { AuthContext } from './AuthContext'
import type { Auth, AuthState, SignedOutReason } from './AuthContext'
import { readRoles } from './roles'
import { setAccessToken } from './token'
import { getUserManager } from './userManager'

// Says who is signed in, to the whole interface (lot 10c). The library keeps the user and the
// tokens in memory and renews the token; this provider follows its events and hands the token
// to the API client.
export default function AuthProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<AuthState>({ status: 'loading' })

  useEffect(() => {
    const manager = getUserManager()

    function signedIn(user: User) {
      setAccessToken(user.access_token)
      setState({
        status: 'signedIn',
        userName: user.profile.preferred_username ?? user.profile.name ?? '',
        roles: readRoles(user.access_token),
      })
    }

    function signedOut(reason?: SignedOutReason) {
      setAccessToken(null)
      setState({ status: 'signedOut', reason })
    }

    manager.getUser().then(
      (user) => (user !== null && user.expired !== true ? signedIn(user) : signedOut()),
      () => signedOut(),
    )

    const removers = [
      // After the sign-in, and each time the token has been renewed.
      manager.events.addUserLoaded(signedIn),
      manager.events.addUserUnloaded(() => signedOut()),
      // The token ran out and could not be renewed.
      manager.events.addAccessTokenExpired(() => signedOut('expired')),
    ]
    return () => removers.forEach((remove) => remove())
  }, [])

  const auth = useMemo<Auth>(
    () => ({
      state,
      signIn: () => {
        // The page leaves for Keycloak. If Keycloak cannot be reached, it stays here.
        getUserManager()
          .signinRedirect()
          .catch(() => {
            setAccessToken(null)
            setState({ status: 'signedOut', reason: 'unreachable' })
          })
      },
      signOut: () => {
        // Ends the session at Keycloak too. If Keycloak cannot be reached, only the local
        // sign-in is removed (case not tried).
        const manager = getUserManager()
        manager.signoutRedirect().catch(() => manager.removeUser())
      },
    }),
    [state],
  )

  return <AuthContext.Provider value={auth}>{children}</AuthContext.Provider>
}
