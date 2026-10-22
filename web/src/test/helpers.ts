// Helpers shared by the tests that replace fetch.
import { vi } from 'vitest'

export function ok(body: unknown): Response {
  return new Response(JSON.stringify(body), { status: 200, headers: { 'Content-Type': 'application/json' } })
}

// A 201: with a body (POST /farms) or without (the other POST routes).
export function created(body?: unknown): Response {
  if (body === undefined) {
    return new Response(null, { status: 201 })
  }
  return new Response(JSON.stringify(body), { status: 201, headers: { 'Content-Type': 'application/json' } })
}

export function problem(status: number, extra: Record<string, unknown> = {}): Response {
  return new Response(JSON.stringify({ title: 'x', status, traceId: '00-abc', ...extra }), {
    status,
    headers: { 'Content-Type': 'application/problem+json' },
  })
}

// Replaces fetch for the length of the test (unstubGlobals puts the real one back).
export function stubFetch(answer: (url: string, init?: RequestInit) => Promise<Response>) {
  const mock = vi.fn(answer)
  vi.stubGlobal('fetch', mock)
  return mock
}

// A fake API: each address (its path) has its own answer. An address nobody planned answers 404.
// Each handler builds a new Response (a Response body can be read only once).
export function stubApi(handlers: Record<string, (url: URL) => Response>) {
  return stubFetch((address) => {
    const url = new URL(address)
    const handler = handlers[url.pathname]
    return Promise.resolve(handler ? handler(url) : problem(404))
  })
}
