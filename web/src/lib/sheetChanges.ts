// What a correction of the sheet of a batch changed (lot 12b), as lines of text. The history of the
// batch page and the message for the recipient both use it.

import { formatDate } from './format'

// The four fields of the sheet of a batch.
export interface SheetValues {
  batchCode: string
  farmCode: string
  variety: string
  harvestDate: string
}

// One line per field that changed, in the order of the sheet: "Code : A → B". A field that did not
// change is not listed. A change of case only (lot-1 → LOT-1) is listed: it is a change.
export function sheetChanges(before: SheetValues, after: SheetValues): string[] {
  const lines: string[] = []
  if (before.batchCode !== after.batchCode) {
    lines.push(`Code : ${before.batchCode} → ${after.batchCode}`)
  }
  if (before.farmCode !== after.farmCode) {
    lines.push(`Ferme : ${before.farmCode} → ${after.farmCode}`)
  }
  if (before.variety !== after.variety) {
    lines.push(`Variété : ${before.variety} → ${after.variety}`)
  }
  if (before.harvestDate !== after.harvestDate) {
    lines.push(`Récolte : ${formatDate(before.harvestDate)} → ${formatDate(after.harvestDate)}`)
  }
  return lines
}
