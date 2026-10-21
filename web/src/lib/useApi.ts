import { useEffect, useState } from 'react'
import { isAbortError } from '../api/errors'

export type ApiState<T> =
  | { status: 'loading' }
  | { status: 'error'; error: unknown }
  | { status: 'success'; data: T }

type Outcome<T> = { status: 'error'; error: unknown } | { status: 'success'; data: T }

// Calls the API when the screen appears and each time `load` changes, and cancels the call that
// is no longer wanted (the user went elsewhere, or changed a filter). An answer to a cancelled
// call is never shown, so a slow old answer cannot replace a newer one.
//
// `load` must keep the same identity while its inputs do not change: wrap it in useCallback,
// with the inputs (a code, a page number...) in its list of dependencies.
//
// The outcome is stored together with the `load` it belongs to. While the stored outcome belongs
// to another `load`, the state is "loading": nothing is set at the start of the effect.
export function useApi<T>(load: (signal: AbortSignal) => Promise<T>): ApiState<T> {
  const [settled, setSettled] = useState<{ load: typeof load; outcome: Outcome<T> } | null>(null)

  useEffect(() => {
    const controller = new AbortController()

    load(controller.signal).then(
      (data) => {
        if (!controller.signal.aborted) {
          setSettled({ load, outcome: { status: 'success', data } })
        }
      },
      (error: unknown) => {
        if (!controller.signal.aborted && !isAbortError(error)) {
          setSettled({ load, outcome: { status: 'error', error } })
        }
      },
    )

    return () => controller.abort()
  }, [load])

  return settled !== null && settled.load === load ? settled.outcome : { status: 'loading' }
}
