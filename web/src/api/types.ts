// Shapes of the answers of the API, copied by hand from
// src/Traceability.Api/Models/Responses.cs (nothing keeps them in sync automatically).
// JSON names are camelCase. They are not checked when the page runs: the API is trusted.
//
// - quantityKg is a JSON number (at most 2 decimals).
// - harvestDate is a day without time ("2026-10-14").
// - occurredAt is a time in UTC that ends with Z.
// - movementId is a 64-bit number in the database; JavaScript reads it exactly up to 2^53.

export const BATCH_STATUSES = ['RECEIVED', 'SORTED', 'PACKED', 'SHIPPED'] as const

export interface Page<T> {
  items: T[]
  totalCount: number
  pageNumber: number
  pageSize: number
}

export interface Farm {
  code: string
  name: string
  region: string
}

export interface Station {
  code: string
  name: string
}

export interface StationDetails {
  code: string
  name: string
  // RECEPTION, SORTING, PACKING, SHIPMENT, in the order of the life cycle.
  capabilities: string[]
}

export interface Batch {
  batchCode: string
  farmCode: string
  variety: string
  harvestDate: string
  quantityKg: number
  status: string
}

export interface Movement {
  movementId: number
  movementType: string
  stationCode: string
  quantityKg: number
  occurredAt: string
}

export interface BatchDetails extends Batch {
  // In the order they were recorded.
  movements: Movement[]
}

// What the web interface sends to the API: the bodies of the POST routes, copied by hand from
// src/Traceability.Api/Models/Requests.cs (nothing keeps them in sync automatically).
//
// - harvestDate is a day without time ("2026-10-14").
// - occurredAt is a time in UTC that must end with Z.
// - quantityKg is a JSON number (more than 0, at most 2 decimals).

export interface NewFarm {
  code: string
  name: string
  region: string
}

export interface NewStation {
  code: string
  name: string
}

export interface NewBatch {
  batchCode: string
  farmCode: string
  variety: string
  harvestDate: string
  quantityKg: number
  stationCode: string
  occurredAt: string
}

export interface NewMovement {
  stationCode: string
  movementType: string
  quantityKg: number
  occurredAt: string
}
