// Shapes of the answers of the API, copied by hand from
// src/Traceability.Api/Models/Responses.cs (nothing keeps them in sync automatically).
// JSON names are camelCase. They are not checked when the page runs: the API is trusted.
//
// - quantityKg is a JSON number (at most 2 decimals).
// - harvestDate is a day without time ("2026-10-14").
// - occurredAt is a time in UTC that ends with Z.
// - movementId is a 64-bit number in the database; JavaScript reads it exactly up to 2^53.

export const BATCH_STATUSES = ['RECEIVED', 'SORTED', 'PACKED', 'SHIPPED'] as const
export const MOVEMENT_TYPES = ['RECEPTION', 'SORTING', 'PACKING', 'SHIPMENT'] as const
// The reasons of a correction (lot 12a).
export const REASON_CODES = ['DATA_ENTRY_ERROR', 'MEASUREMENT_ERROR', 'OTHER'] as const
// The reasons accepted for a correction of the sheet of a batch (lot 12b). A measurement error does
// not apply to a sheet: the API refuses it (error 50407).
export const SHEET_REASON_CODES = ['DATA_ENTRY_ERROR', 'OTHER'] as const

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
  // The user name of the author at the time of the entry (lot 11). The API never sends the
  // identifier of the author. The first data of the database have the author "Initial_User".
  // Lot 12b: null when the API does not show the names of the authors to the signed-in role (only
  // the auditor and the supervisor see them).
  authorName: string | null
  // Lot 12a: stationCode, quantityKg and occurredAt above are the VALID values (the latest
  // correction applied). The original* fields are the values first entered. A cancelled movement
  // did not happen: it stays in the list with isCancelled true.
  isCancelled: boolean
  correctionCount: number
  originalStationCode: string
  originalQuantityKg: number
  originalOccurredAt: string
}

// One correction of a movement (lot 12a). kind is REPLACE or CANCEL; a CANCEL repeats the values of
// the version it cancels. authorName is the name of the supervisor at the time of the correction
// (null when the API does not show the names of the authors to the signed-in role, lot 12b).
export interface Correction {
  correctionId: number
  movementId: number
  kind: string
  movementType: string
  stationCode: string
  quantityKg: number
  occurredAt: string
  reasonCode: string
  reasonComment: string
  authorName: string | null
  correctedAt: string
}

// One correction of the sheet of a batch (lot 12b): the old and the new value of the four fields
// of the sheet (the fields that did not change have the same old and new value). harvestDate is a
// day without time. authorName is null when the API does not show the names of the authors to the
// signed-in role. The API never sends the identifier of the author.
export interface SheetCorrection {
  correctionId: number
  oldBatchCode: string
  newBatchCode: string
  oldFarmCode: string
  newFarmCode: string
  oldVariety: string
  newVariety: string
  oldHarvestDate: string
  newHarvestDate: string
  reasonCode: string
  reasonComment: string
  authorName: string | null
  correctedAt: string
}

export interface BatchDetails extends Batch {
  // In the order they were recorded, cancelled ones included.
  movements: Movement[]
  // The corrections of the movements, in the order they were made.
  corrections: Correction[]
  // The corrections of the sheet of the batch (lot 12b), in the order they were made.
  sheetCorrections: SheetCorrection[]
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

// The bodies of the correction routes (lot 12a). The reason comment may be empty, except for the
// reason OTHER. occurredAt must end with Z.
export interface NewReplacement {
  stationCode: string
  quantityKg: number
  occurredAt: string
  reasonCode: string
  reasonComment: string
}

export interface NewCancellation {
  reasonCode: string
  reasonComment: string
}

// The body of the route that corrects the sheet of a batch (lot 12b). The four fields of the sheet
// are all sent, with the new values (the values that do not change are sent again). harvestDate is
// a day without time. The reason comment may be empty, except for the reason OTHER.
export interface NewSheetCorrection {
  newBatchCode: string
  farmCode: string
  variety: string
  harvestDate: string
  reasonCode: string
  reasonComment: string
}
