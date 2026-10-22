// @vitest-environment jsdom

import { act, cleanup, renderHook } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { ApiError } from '../api/errors'
import { useApi } from './useApi'

afterEach(cleanup)

function deferred<T>() {
  let resolve!: (value: T) => void
  let reject!: (error: unknown) => void
  const promise = new Promise<T>((res, rej) => {
    resolve = res
    reject = rej
  })
  return { promise, resolve, reject }
}

describe('useApi', () => {
  it('is loading, then gives the data', async () => {
    const call = deferred<string>()
    const load = () => call.promise
    const { result } = renderHook(() => useApi(load))

    expect(result.current).toEqual({ status: 'loading' })

    await act(async () => call.resolve('data'))

    expect(result.current).toEqual({ status: 'success', data: 'data' })
  })

  it('gives the error', async () => {
    const call = deferred<string>()
    const error = new ApiError({ status: 500 })
    const load = () => call.promise
    const { result } = renderHook(() => useApi(load))

    await act(async () => call.reject(error))

    expect(result.current).toEqual({ status: 'error', error })
  })

  it('goes back to loading when the call changes', async () => {
    const first = deferred<string>()
    const second = deferred<string>()
    const { result, rerender } = renderHook(({ load }) => useApi(load), {
      initialProps: { load: () => first.promise },
    })
    await act(async () => first.resolve('A'))
    expect(result.current).toEqual({ status: 'success', data: 'A' })

    rerender({ load: () => second.promise })

    expect(result.current).toEqual({ status: 'loading' })
  })

  it('never shows the slow answer of a call that was replaced', async () => {
    const first = deferred<string>()
    const second = deferred<string>()
    const { result, rerender } = renderHook(({ load }) => useApi(load), {
      // These calls ignore the signal: they answer even after being cancelled, like a slow network.
      initialProps: { load: () => first.promise },
    })

    rerender({ load: () => second.promise })
    await act(async () => second.resolve('B'))
    await act(async () => first.resolve('A'))

    expect(result.current).toEqual({ status: 'success', data: 'B' })
  })

  it('does not show a cancelled call as an error', async () => {
    const call = deferred<string>()
    const { result, rerender } = renderHook(({ load }) => useApi(load), {
      initialProps: { load: () => call.promise },
    })

    rerender({ load: () => new Promise<string>(() => {}) })
    await act(async () => call.reject(new DOMException('aborted', 'AbortError')))

    expect(result.current).toEqual({ status: 'loading' })
  })

  // A second number given to useApi (`refresh`) makes it read again, with the same `load`.
  // `load` gives the answers of `answers` one after the other: the first call, then the second.
  function renderWithRefresh(answers: ReturnType<typeof deferred<string>>[]) {
    const load = vi.fn(() => answers.shift()!.promise)
    const hook = renderHook(({ refresh }) => useApi(load, refresh), { initialProps: { refresh: 0 } })
    return { load, ...hook }
  }

  it('keeps the data on screen while it reads again when the refresh number changes', async () => {
    const first = deferred<string>()
    const second = deferred<string>()
    const { load, result, rerender } = renderWithRefresh([first, second])
    await act(async () => first.resolve('A'))

    rerender({ refresh: 1 })

    expect(load).toHaveBeenCalledTimes(2)
    expect(result.current).toEqual({ status: 'success', data: 'A' })

    await act(async () => second.resolve('B'))

    expect(result.current).toEqual({ status: 'success', data: 'B' })
  })

  it('never shows the slow answer of a read that was replaced by a refresh', async () => {
    const first = deferred<string>()
    const second = deferred<string>()
    const { result, rerender } = renderWithRefresh([first, second])

    rerender({ refresh: 1 })
    await act(async () => second.resolve('B'))
    await act(async () => first.resolve('A'))

    expect(result.current).toEqual({ status: 'success', data: 'B' })
  })

  it('shows the error when the new read fails', async () => {
    const first = deferred<string>()
    const second = deferred<string>()
    const error = new ApiError({ status: 500 })
    const { result, rerender } = renderWithRefresh([first, second])
    await act(async () => first.resolve('A'))

    rerender({ refresh: 1 })
    await act(async () => second.reject(error))

    expect(result.current).toEqual({ status: 'error', error })
  })
})
