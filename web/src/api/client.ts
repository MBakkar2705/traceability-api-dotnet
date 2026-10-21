// The only module that calls the API: one function per route (the 5 GET routes of the lot 4a).
// A call can be cancelled with an AbortSignal.

import { API_BASE_URL } from '../config'
import { ApiError, NetworkError, isAbortError } from './errors'
import type { Batch, BatchDetails, Farm, Page, Station, StationDetails } from './types'

export interface PageParams {
  pageNumber?: number
  pageSize?: number
}

export interface BatchFilters extends PageParams {
  status?: string
  farmCode?: string
}

type Query = Record<string, string | number | undefined>

// Builds the address. A value that is undefined or empty is left out of the query string.
export function buildUrl(path: string, query: Query = {}): string {
  const url = new URL(path, API_BASE_URL)
  for (const [name, value] of Object.entries(query)) {
    if (value !== undefined && value !== '') {
      url.searchParams.set(name, String(value))
    }
  }
  return url.toString()
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function toFieldErrors(value: unknown): Record<string, string[]> | undefined {
  if (!isRecord(value)) {
    return undefined
  }
  const fieldErrors: Record<string, string[]> = {}
  for (const [field, messages] of Object.entries(value)) {
    if (Array.isArray(messages)) {
      fieldErrors[field] = messages.filter((message): message is string => typeof message === 'string')
    }
  }
  return fieldErrors
}

// Reads the Problem Details of an error answer. If the body is not what we expect, we keep
// at least the status.
export async function toApiError(response: Response): Promise<ApiError> {
  let body: unknown
  try {
    body = await response.json()
  } catch {
    body = undefined
  }
  const problem = isRecord(body) ? body : {}
  return new ApiError({
    status: response.status,
    errorCode: typeof problem.errorCode === 'number' ? problem.errorCode : undefined,
    detail: typeof problem.detail === 'string' ? problem.detail : undefined,
    traceId: typeof problem.traceId === 'string' ? problem.traceId : undefined,
    fieldErrors: toFieldErrors(problem.errors),
  })
}

async function getJson<T>(path: string, query: Query, signal?: AbortSignal): Promise<T> {
  let response: Response
  try {
    response = await fetch(buildUrl(path, query), { headers: { Accept: 'application/json' }, signal })
  } catch (error) {
    if (isAbortError(error)) {
      throw error
    }
    throw new NetworkError({ cause: error })
  }

  if (!response.ok) {
    throw await toApiError(response)
  }
  return (await response.json()) as T
}

const segment = encodeURIComponent

export function listFarms(params: PageParams = {}, signal?: AbortSignal): Promise<Page<Farm>> {
  return getJson('/farms', { pageNumber: params.pageNumber, pageSize: params.pageSize }, signal)
}

export function listStations(params: PageParams = {}, signal?: AbortSignal): Promise<Page<Station>> {
  return getJson('/stations', { pageNumber: params.pageNumber, pageSize: params.pageSize }, signal)
}

export function getStation(stationCode: string, signal?: AbortSignal): Promise<StationDetails> {
  return getJson(`/stations/${segment(stationCode)}`, {}, signal)
}

export function listBatches(filters: BatchFilters = {}, signal?: AbortSignal): Promise<Page<Batch>> {
  return getJson(
    '/batches',
    {
      status: filters.status,
      farmCode: filters.farmCode,
      pageNumber: filters.pageNumber,
      pageSize: filters.pageSize,
    },
    signal,
  )
}

export function getBatch(batchCode: string, signal?: AbortSignal): Promise<BatchDetails> {
  return getJson(`/batches/${segment(batchCode)}`, {}, signal)
}
