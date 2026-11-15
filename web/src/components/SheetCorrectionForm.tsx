import type { FormEvent } from 'react'
import { correctBatch } from '../api/client'
import { SHEET_REASON_CODES } from '../api/types'
import { reasonLabel } from '../lib/labels'
import type { SheetCorrectionSummary } from '../lib/recipientMessage'
import type { SheetValues } from '../lib/sheetChanges'
import { useSubmit } from '../lib/useSubmit'
import Field from './Field'
import FormAlert from './FormAlert'
import { BUTTON, FIELD } from './styles'

// The names of the fields in the API (and of the inputs).
const FIELD_NAMES = ['newBatchCode', 'farmCode', 'variety', 'harvestDate', 'reasonCode', 'reasonComment']

// The code 50203 also means "this station already has this function" for a station: here it says
// that the new code is the old code of another batch.
const OWN_MESSAGES = { 50203: "Ce code est l'ancien code d'un autre lot." }

interface SheetCorrectionFormProps {
  // The code of the address of the page: the API finds the batch by its current code.
  batchCode: string
  // The current values of the sheet: they fill the form.
  sheet: SheetValues
  // Called when a new attempt starts: the page forgets the message of the last success.
  onStart: () => void
  // Called when the correction has been recorded: the page reads the batch again, or opens it under
  // its new code.
  onCorrected: (summary: SheetCorrectionSummary) => void
}

// The form that corrects the sheet of a batch: its code, its farm, its variety, its harvest day
// (lot 12b). It only proposes: the rules (a code already taken, a harvest after the reception, a
// farm that does not exist) are applied by the API, which says why when it refuses. The page gives
// it a `key` that changes after each correction, so that it starts again with the new values.
export default function SheetCorrectionForm({ batchCode, sheet, onStart, onCorrected }: SheetCorrectionFormProps) {
  const { state, submit } = useSubmit(OWN_MESSAGES)
  const fieldMessages = state.status === 'error' ? state.error.fieldMessages : {}
  const sending = state.status === 'sending'

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const data = new FormData(event.currentTarget)
    const text = (name: string) => String(data.get(name) ?? '')
    // What was typed is sent as it is: if the API refuses it, it says why.
    const correction = {
      newBatchCode: text('newBatchCode'),
      farmCode: text('farmCode'),
      variety: text('variety'),
      harvestDate: text('harvestDate'),
      reasonCode: text('reasonCode'),
      reasonComment: text('reasonComment'),
    }

    onStart()
    if (await submit(() => correctBatch(batchCode, correction))) {
      onCorrected({
        before: sheet,
        after: {
          batchCode: correction.newBatchCode,
          farmCode: correction.farmCode,
          variety: correction.variety,
          harvestDate: correction.harvestDate,
        },
        reasonCode: correction.reasonCode,
        reasonComment: correction.reasonComment,
      })
    }
  }

  return (
    <form
      onSubmit={handleSubmit}
      className="flex max-w-md flex-col gap-3 rounded border border-edge-strong bg-paper p-4 shadow-sm"
    >
      {state.status === 'error' && <FormAlert error={state.error} fieldNames={FIELD_NAMES} />}

      <Field label="Code du lot" messages={fieldMessages.newBatchCode}>
        <input
          name="newBatchCode"
          required
          maxLength={20}
          defaultValue={sheet.batchCode}
          className={`${FIELD} font-mono`}
        />
      </Field>
      <Field label="Code de la ferme" messages={fieldMessages.farmCode}>
        <input
          name="farmCode"
          required
          maxLength={20}
          defaultValue={sheet.farmCode}
          className={`${FIELD} font-mono`}
        />
      </Field>
      <Field label="Variété" messages={fieldMessages.variety}>
        <input name="variety" required maxLength={100} defaultValue={sheet.variety} className={FIELD} />
      </Field>
      <Field label="Date de récolte" messages={fieldMessages.harvestDate}>
        <input name="harvestDate" type="date" required defaultValue={sheet.harvestDate} className={FIELD} />
      </Field>

      <Field label="Motif" messages={fieldMessages.reasonCode}>
        <select name="reasonCode" defaultValue="DATA_ENTRY_ERROR" className={FIELD}>
          {SHEET_REASON_CODES.map((code) => (
            <option key={code} value={code}>
              {reasonLabel(code)}
            </option>
          ))}
        </select>
      </Field>
      <Field label="Commentaire (obligatoire pour « Autre »)" messages={fieldMessages.reasonComment}>
        <textarea name="reasonComment" rows={3} maxLength={500} className={FIELD} />
      </Field>

      <button type="submit" disabled={sending} className={BUTTON}>
        {sending ? 'Envoi…' : 'Corriger la fiche'}
      </button>
    </form>
  )
}
