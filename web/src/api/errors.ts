// What can go wrong when the web interface calls the API.

export interface ApiErrorDetails {
  status: number
  // The SQL number of an error raised by a stored procedure (for example 50100). Absent for
  // errors of shape (malformed code, unreadable number) and for unexpected errors.
  errorCode?: number
  // The English text sent by the API.
  detail?: string
  traceId?: string
  // Errors of shape: each field with its list of messages.
  fieldErrors?: Record<string, string[]>
}

/** The API answered, with an error status (Problem Details). */
export class ApiError extends Error {
  readonly status: number
  readonly errorCode?: number
  readonly detail?: string
  readonly traceId?: string
  readonly fieldErrors?: Record<string, string[]>

  constructor(details: ApiErrorDetails) {
    super(`The API answered ${details.status}` + (details.errorCode === undefined ? '' : ` (error ${details.errorCode})`))
    this.name = 'ApiError'
    this.status = details.status
    this.errorCode = details.errorCode
    this.detail = details.detail
    this.traceId = details.traceId
    this.fieldErrors = details.fieldErrors
  }
}

/** The API did not answer: it is stopped, unreachable, or the browser blocked the call. */
export class NetworkError extends Error {
  constructor(options?: { cause?: unknown }) {
    super('The API could not be reached.', options)
    this.name = 'NetworkError'
  }
}

/** A call cancelled on purpose (the screen changed): not an error to show. */
export function isAbortError(error: unknown): boolean {
  return error instanceof DOMException && error.name === 'AbortError'
}
