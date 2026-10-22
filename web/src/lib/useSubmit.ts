import { useRef, useState } from 'react'
import { describeWriteError } from './messages'
import type { WriteErrorMessage } from './messages'

export type SubmitState =
  | { status: 'idle' }
  | { status: 'sending' }
  | { status: 'error'; error: WriteErrorMessage }

// Sends a form: `submit(action)` runs the call (a write to the API) and says whether it worked.
// While a call is running, another `submit` does nothing and says false, so a double click sends
// only one request. The guard is a ref and not the state: two clicks very close together can come
// before the screen has been drawn again with the disabled button.
export function useSubmit() {
  const [state, setState] = useState<SubmitState>({ status: 'idle' })
  const sending = useRef(false)

  async function submit(action: () => Promise<unknown>): Promise<boolean> {
    if (sending.current) {
      return false
    }
    sending.current = true
    setState({ status: 'sending' })
    try {
      await action()
      setState({ status: 'idle' })
      return true
    } catch (error) {
      setState({ status: 'error', error: describeWriteError(error) })
      return false
    } finally {
      sending.current = false
    }
  }

  return { state, submit }
}
