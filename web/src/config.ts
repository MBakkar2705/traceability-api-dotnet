// Address of the API. VITE_API_URL can override it, for example in a local file
// web/.env.local (git ignores *.local files). Its value ends up in the code sent to the
// browser: never put a secret in a VITE_ variable.
export const API_BASE_URL: string = import.meta.env.VITE_API_URL ?? 'https://localhost:7080'

// Sign-in (lot 10c). The address of the realm of Keycloak and the name of the client of this
// interface (identity/traceability-realm.json). The client is public: there is no secret, and
// there must never be one in a VITE_ variable.
export const AUTH_AUTHORITY: string = import.meta.env.VITE_AUTH_AUTHORITY ?? 'http://localhost:8180/realms/traceability'
export const AUTH_CLIENT_ID: string = import.meta.env.VITE_AUTH_CLIENT_ID ?? 'traceability-web'

// Items per page in the lists (the API accepts 1 to 1000; the interface of the lot 4a does not let the user choose).
// 15 rows (with compact rows) fit on a laptop screen without scrolling.
export const PAGE_SIZE = 15
