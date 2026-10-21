import { describe, expect, it } from 'vitest'
import { ok, problem, stubFetch } from '../test/helpers'
import { buildUrl, getBatch, getStation, listBatches, listFarms } from './client'
import { ApiError, NetworkError, isAbortError } from './errors'

const BASE = 'https://localhost:7080'

describe('buildUrl', () => {
  it('adds no query string when there is nothing to add', () => {
    expect(buildUrl('/farms')).toBe(`${BASE}/farms`)
  })

  it('leaves out the values that are undefined or empty', () => {
    const url = buildUrl('/batches', { status: 'SHIPPED', farmCode: '', pageNumber: 2, pageSize: undefined })

    expect(url).toBe(`${BASE}/batches?status=SHIPPED&pageNumber=2`)
  })
})

describe('the calls', () => {
  it('sends the address, the Accept header and the signal, and returns the JSON', async () => {
    const page = { items: [], totalCount: 0, pageNumber: 1, pageSize: 20 }
    const fetchMock = stubFetch(() => Promise.resolve(ok(page)))
    const controller = new AbortController()

    const result = await listFarms({ pageNumber: 1, pageSize: 20 }, controller.signal)

    expect(result).toEqual(page)
    expect(fetchMock).toHaveBeenCalledWith(`${BASE}/farms?pageNumber=1&pageSize=20`, {
      headers: { Accept: 'application/json' },
      signal: controller.signal,
    })
  })

  it('does not send the filters that are empty', async () => {
    const fetchMock = stubFetch(() => Promise.resolve(ok({})))

    await listBatches({ status: 'SHIPPED', farmCode: '' })

    expect(fetchMock.mock.calls[0][0]).toBe(`${BASE}/batches?status=SHIPPED`)
  })

  it('writes a code in the address without breaking it', async () => {
    const fetchMock = stubFetch(() => Promise.resolve(ok({})))

    await getBatch('A B/1')
    await getStation('SITE-01')

    expect(fetchMock.mock.calls[0][0]).toBe(`${BASE}/batches/A%20B%2F1`)
    expect(fetchMock.mock.calls[1][0]).toBe(`${BASE}/stations/SITE-01`)
  })
})

describe('the errors', () => {
  it('turns the error of a stored procedure into an ApiError with its code', async () => {
    stubFetch(() => Promise.resolve(problem(404, { errorCode: 50100, detail: 'Batch not found.' })))

    const error = await getBatch('ZT-1').catch((e: unknown) => e)

    expect(error).toBeInstanceOf(ApiError)
    expect(error).toMatchObject({ status: 404, errorCode: 50100, detail: 'Batch not found.', traceId: '00-abc' })
  })

  it('keeps the messages of each field for an error of shape (no error code)', async () => {
    stubFetch(() => Promise.resolve(problem(400, { errors: { pageNumber: ['The value is not valid.'] } })))

    const error = await listFarms().catch((e: unknown) => e)

    expect(error).toBeInstanceOf(ApiError)
    expect(error).toMatchObject({ status: 400, fieldErrors: { pageNumber: ['The value is not valid.'] } })
    expect((error as ApiError).errorCode).toBeUndefined()
  })

  it('keeps the status of an unexpected error', async () => {
    stubFetch(() => Promise.resolve(problem(500)))

    const error = await listFarms().catch((e: unknown) => e)

    expect(error).toBeInstanceOf(ApiError)
    expect(error).toMatchObject({ status: 500, traceId: '00-abc' })
    expect((error as ApiError).errorCode).toBeUndefined()
  })

  it('keeps the status when the body is not Problem Details (for example HTML)', async () => {
    stubFetch(() =>
      Promise.resolve(new Response('<html>Bad gateway</html>', { status: 502, headers: { 'Content-Type': 'text/html' } })),
    )

    const error = await listFarms().catch((e: unknown) => e)

    expect(error).toBeInstanceOf(ApiError)
    expect((error as ApiError).status).toBe(502)
    expect((error as ApiError).errorCode).toBeUndefined()
    expect((error as ApiError).detail).toBeUndefined()
  })

  it('says NetworkError when the API cannot be reached, and keeps the cause', async () => {
    const cause = new TypeError('Failed to fetch')
    stubFetch(() => Promise.reject(cause))

    const error = await listFarms().catch((e: unknown) => e)

    expect(error).toBeInstanceOf(NetworkError)
    expect((error as NetworkError).cause).toBe(cause)
  })

  it('lets a cancelled call through as it is, so the screen can ignore it', async () => {
    const aborted = new DOMException('The operation was aborted.', 'AbortError')
    stubFetch(() => Promise.reject(aborted))

    await expect(getBatch('ZT-1')).rejects.toBe(aborted)
    expect(isAbortError(aborted)).toBe(true)
    expect(isAbortError(new Error('boom'))).toBe(false)
  })
})
