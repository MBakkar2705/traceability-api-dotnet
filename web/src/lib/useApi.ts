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
// `refresh` is a number that the page raises after a write: the API is then called again with the
// same `load`, and the previous answer stays on screen until the new one comes.
//
// `load` must keep the same identity while its inputs do not change: wrap it in useCallback,
// with the inputs (a code, a page number...) in its list of dependencies.
//
// The outcome is stored together with the `load` it belongs to. While the stored outcome belongs
// to another `load`, the state is "loading": nothing is set at the start of the effect. A new
// `refresh` does not change `load`, which is why the previous outcome stays.
export function useApi<T>(load: (signal: AbortSignal) => Promise<T>, refresh = 0): ApiState<T> {
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
  }, [load, refresh])

  return settled !== null && settled.load === load ? settled.outcome : { status: 'loading' }
}
