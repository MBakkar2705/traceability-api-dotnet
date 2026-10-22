// @vitest-environment jsdom

import { act, cleanup, renderHook } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { ApiError } from '../api/errors'
import { useSubmit } from './useSubmit'

afterEach(cleanup)

function deferred<T>() {
  let resolve!: (value: T) => void
  const promise = new Promise<T>((res) => {
    resolve = res
  })
  return { promise, resolve }
}

describe('useSubmit', () => {
  it('is idle at first', () => {
    const { result } = renderHook(() => useSubmit())

    expect(result.current.state).toEqual({ status: 'idle' })
  })

  it('is sending while the call runs, then idle again, and says that it worked', async () => {
    const call = deferred<void>()
    const { result } = renderHook(() => useSubmit())

    let worked: Promise<boolean> | undefined
    act(() => {
      worked = result.current.submit(() => call.promise)
    })
    expect(result.current.state).toEqual({ status: 'sending' })

    await act(async () => call.resolve())

    expect(await worked).toBe(true)
    expect(result.current.state).toEqual({ status: 'idle' })
  })

  it('gives the error in French and says that it failed', async () => {
    const { result } = renderHook(() => useSubmit())

    let worked: boolean | undefined
    await act(async () => {
      worked = await result.current.submit(() => Promise.reject(new ApiError({ status: 409, errorCode: 50200 })))
    })

    expect(worked).toBe(false)
    expect(result.current.state).toMatchObject({
      status: 'error',
      error: { message: 'Une ferme porte déjà ce code.' },
    })
  })

  it('ignores a second send while the first one is running', async () => {
    const first = deferred<void>()
    const second = vi.fn(() => Promise.resolve())
    const { result } = renderHook(() => useSubmit())

    let firstWorked: Promise<boolean> | undefined
    act(() => {
      firstWorked = result.current.submit(() => first.promise)
    })
    let secondWorked: boolean | undefined
    await act(async () => {
      secondWorked = await result.current.submit(second)
    })

    expect(secondWorked).toBe(false)
    expect(second).not.toHaveBeenCalled()

    await act(async () => first.resolve())
    expect(await firstWorked).toBe(true)
  })

  it('can send again after an error, and the error goes away', async () => {
    const { result } = renderHook(() => useSubmit())

    await act(async () => {
      await result.current.submit(() => Promise.reject(new Error('boom')))
    })
    expect(result.current.state.status).toBe('error')

    await act(async () => {
      await result.current.submit(() => Promise.resolve())
    })

    expect(result.current.state).toEqual({ status: 'idle' })
  })
})
