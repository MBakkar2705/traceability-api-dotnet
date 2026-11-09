// The access token that the API client sends (lot 10c). It lives in memory only: the sign-in
// provider sets it when someone signs in and clears it when they sign out, and nothing here
// writes it to a storage of the browser (ADR 0014).
let accessToken: string | null = null

export function setAccessToken(token: string | null): void {
  accessToken = token
}

export function getAccessToken(): string | null {
  return accessToken
}
