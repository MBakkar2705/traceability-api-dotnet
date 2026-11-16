// The message that a supervisor can copy and send to the recipient of a batch that was already
// shipped, when one of its movements is corrected (lot 12a), or its sheet (lot 12b). The application
// does not send it and does not record that it was sent: the supervisor, or the sales contact,
// forwards it.

import { formatKg, formatUtc } from './format'
import { movementLabel, reasonLabel } from './labels'
import { sheetChanges } from './sheetChanges'
import type { SheetValues } from './sheetChanges'

export interface MovementValues {
  stationCode: string
  quantityKg: number
  occurredAt: string
}

export interface CorrectionSummary {
  kind: 'REPLACE' | 'CANCEL'
  batchCode: string
  movementType: string
  // The valid values before the correction.
  before: MovementValues
  // The new values (only for REPLACE).
  after?: MovementValues
  reasonCode: string
  reasonComment: string
}

// Only what changed is listed: a recipient does not need the values that stay the same.
function changes(before: MovementValues, after: MovementValues): string[] {
  const lines: string[] = []
  if (before.quantityKg !== after.quantityKg) {
    lines.push(`- Quantité : ${formatKg(before.quantityKg)} → ${formatKg(after.quantityKg)}`)
  }
  if (before.stationCode !== after.stationCode) {
    lines.push(`- Station : ${before.stationCode} → ${after.stationCode}`)
  }
  if (formatUtc(before.occurredAt) !== formatUtc(after.occurredAt)) {
    lines.push(`- Date et heure : ${formatUtc(before.occurredAt)} → ${formatUtc(after.occurredAt)}`)
  }
  return lines
}

// The end of every message: the reason (with the comment, if there is one), a request, a closing.
function ending(reasonCode: string, reasonComment: string): string[] {
  const comment = reasonComment.trim()
  return [
    '',
    `Motif : ${reasonLabel(reasonCode)}${comment === '' ? '' : ` (${comment})`}.`,
    '',
    'Merci de tenir compte de cette correction.',
    '',
    'Cordialement',
  ]
}

export function recipientMessage(summary: CorrectionSummary): string {
  const step = movementLabel(summary.movementType).toLowerCase()
  const lines = ['Bonjour,', '']

  if (summary.kind === 'CANCEL') {
    lines.push(
      `Une correction a été enregistrée sur le lot ${summary.batchCode} : l'étape « ${step} » est annulée, elle n'a pas eu lieu.`,
    )
  } else {
    lines.push(`Une correction a été enregistrée sur le lot ${summary.batchCode} (étape « ${step} »).`)
    const listed = summary.after === undefined ? [] : changes(summary.before, summary.after)
    if (listed.length > 0) {
      lines.push('Valeurs corrigées :', ...listed)
    }
  }

  lines.push(...ending(summary.reasonCode, summary.reasonComment))
  return lines.join('\n')
}

// A correction of the sheet of a batch (lot 12b): the values before and after.
export interface SheetCorrectionSummary {
  before: SheetValues
  after: SheetValues
  reasonCode: string
  reasonComment: string
}

// Only what changed is listed. When the code changes, the message says which code to use from now
// on; it says nothing about the application, which the recipient may not use.
export function sheetRecipientMessage(summary: SheetCorrectionSummary): string {
  const oldCode = summary.before.batchCode
  const lines = ['Bonjour,', '', `Une correction a été enregistrée sur la fiche du lot ${oldCode}.`]
  const listed = sheetChanges(summary.before, summary.after)
  if (listed.length > 0) {
    lines.push('Valeurs corrigées :', ...listed.map((line) => `- ${line}`))
  }
  if (summary.before.batchCode !== summary.after.batchCode) {
    lines.push(`Le lot doit maintenant être désigné par le code ${summary.after.batchCode}.`)
  }
  lines.push(...ending(summary.reasonCode, summary.reasonComment))
  return lines.join('\n')
}
