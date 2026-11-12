// The message that a supervisor can copy and send to the recipient of a batch that was already
// shipped, when one of its movements is corrected (lot 12a). The application does not send it and
// does not record that it was sent: the supervisor, or the sales contact, forwards it.

import { formatKg, formatUtc } from './format'
import { movementLabel, reasonLabel } from './labels'

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

  const comment = summary.reasonComment.trim()
  lines.push('', `Motif : ${reasonLabel(summary.reasonCode)}${comment === '' ? '' : ` (${comment})`}.`)
  lines.push('', 'Merci de tenir compte de cette correction.', '', 'Cordialement')
  return lines.join('\n')
}
