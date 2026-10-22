import { describe, expect, it } from 'vitest'
import { created, ok, problem, stubFetch } from '../test/helpers'
import {
  addCapability,
  addMovement,
  buildUrl,
  createBatch,
  createFarm,
  createStation,
  getBatch,
  getStation,
  listBatches,
  listFarms,
} from './client'
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

const farm = { code: 'ZT-FARM', name: 'Test farm', region: 'Region A' }
const station = { code: 'ZT-STATION', name: 'Test station' }
const batch = {
  batchCode: 'ZT-BATCH',
  farmCode: 'ZT-FARM',
  variety: 'Roma',
  harvestDate: '2026-10-14',
  quantityKg: 120.5,
  stationCode: 'ZT-STATION',
  occurredAt: '2026-10-14T06:00:00Z',
}
const movement = {
  stationCode: 'ZT-STATION',
  movementType: 'SORTING',
  quantityKg: 110,
  occurredAt: '2026-10-14T08:00:00Z',
}

describe('the writes', () => {
  const postInit = (body: unknown) => ({
    method: 'POST',
    headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })

  it('sends the farm as JSON with POST and returns the farm of the answer', async () => {
    const fetchMock = stubFetch(() => Promise.resolve(created(farm)))

    const result = await createFarm(farm)

    expect(result).toEqual(farm)
    expect(fetchMock).toHaveBeenCalledWith(`${BASE}/farms`, postInit(farm))
  })

  it.each([
    { name: 'createStation', call: () => createStation(station), path: '/stations', body: station },
    {
      name: 'addCapability',
      call: () => addCapability('ZT-STATION', 'PACKING'),
      path: '/stations/ZT-STATION/capabilities',
      body: { movementType: 'PACKING' },
    },
    { name: 'createBatch', call: () => createBatch(batch), path: '/batches', body: batch },
    {
      name: 'addMovement',
      call: () => addMovement('ZT-BATCH', movement),
      path: '/batches/ZT-BATCH/movements',
      body: movement,
    },
  ])('$name sends its body with POST and accepts an answer 201 with no body', async ({ call, path, body }) => {
    const fetchMock = stubFetch(() => Promise.resolve(created()))

    await expect(call()).resolves.toBeUndefined()

    expect(fetchMock).toHaveBeenCalledWith(`${BASE}${path}`, postInit(body))
  })

  it('writes a code in the address without breaking it', async () => {
    const fetchMock = stubFetch(() => Promise.resolve(created()))

    await addCapability('A B/1', 'PACKING')
    await addMovement('A B/1', movement)

    expect(fetchMock.mock.calls[0][0]).toBe(`${BASE}/stations/A%20B%2F1/capabilities`)
    expect(fetchMock.mock.calls[1][0]).toBe(`${BASE}/batches/A%20B%2F1/movements`)
  })

  it('sends no signal: a write is never cancelled half way', async () => {
    const fetchMock = stubFetch(() => Promise.resolve(created()))

    await createStation(station)

    const init = fetchMock.mock.calls[0][1] as RequestInit
    expect('signal' in init).toBe(false)
  })

  it('turns a 409 of a stored procedure into an ApiError with its code', async () => {
    stubFetch(() => Promise.resolve(problem(409, { errorCode: 50200, detail: 'Farm code already taken.' })))

    const error = await createFarm(farm).catch((e: unknown) => e)

    expect(error).toBeInstanceOf(ApiError)
    expect(error).toMatchObject({ status: 409, errorCode: 50200 })
  })

  it('keeps the messages of each field when the API refuses the shape (400)', async () => {
    const errors = { code: ['The field is required.'], name: ['At most 100 characters are allowed.'] }
    stubFetch(() => Promise.resolve(problem(400, { errors })))

    const error = await createFarm(farm).catch((e: unknown) => e)

    expect(error).toBeInstanceOf(ApiError)
    expect(error).toMatchObject({ status: 400, fieldErrors: errors })
    expect((error as ApiError).errorCode).toBeUndefined()
  })

  it('says NetworkError when the API cannot be reached, and calls fetch once', async () => {
    const cause = new TypeError('Failed to fetch')
    const fetchMock = stubFetch(() => Promise.reject(cause))

    const error = await addMovement('ZT-BATCH', movement).catch((e: unknown) => e)

    expect(error).toBeInstanceOf(NetworkError)
    expect((error as NetworkError).cause).toBe(cause)
    expect(fetchMock).toHaveBeenCalledTimes(1)
  })
})
