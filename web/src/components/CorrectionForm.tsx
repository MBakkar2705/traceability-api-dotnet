import { useState } from 'react'
import type { FormEvent } from 'react'
import { cancelMovement, replaceMovement } from '../api/client'
import { REASON_CODES } from '../api/types'
import type { Movement } from '../api/types'
import { formatKg, formatUtc } from '../lib/format'
import { movementLabel, reasonLabel } from '../lib/labels'
import type { CorrectionSummary } from '../lib/recipientMessage'
import { useSubmit } from '../lib/useSubmit'
import { toUtcText } from '../lib/utc'
import Field from './Field'
import FormAlert from './FormAlert'
import { BUTTON, FIELD } from './styles'

// The names of the fields in the API (and of the inputs).
const FIELD_NAMES = ['stationCode', 'quantityKg', 'occurredAt', 'reasonCode', 'reasonComment']

type Action = 'replace' | 'cancel'

interface CorrectionFormProps {
  batchCode: string
  // All the movements of the batch: the form proposes those that are not cancelled.
  movements: Movement[]
  // Called when a new attempt starts: the page forgets the message of the last success.
  onStart: () => void
  // Called when the correction has been recorded: the page reads the batch again.
  onCorrected: (summary: CorrectionSummary) => void
}

// The value of an <input type="datetime-local" step="1"> for a time of the API (UTC, ends with Z).
const toInputTime = (occurredAt: string): string => occurredAt.slice(0, 19)

// The form that replaces the values of a movement, or says that it did not happen (lot 12a). It only
// proposes: the rules (which movement can be cancelled, how far the quantity can go) are applied
// by the API, which says why when it refuses. The page gives it a `key` that changes after each
// correction, so that it starts again.
export default function CorrectionForm({ batchCode, movements, onStart, onCorrected }: CorrectionFormProps) {
  const { state, submit } = useSubmit()
  const valid = movements.filter((movement) => !movement.isCancelled)
  // The last valid movement is the one most often corrected (and the only one that can be cancelled).
  const [selectedId, setSelectedId] = useState(String(valid.at(-1)?.movementId ?? ''))
  const [action, setAction] = useState<Action>('replace')
  const fieldMessages = state.status === 'error' ? state.error.fieldMessages : {}
  const sending = state.status === 'sending'
  const movement = valid.find((candidate) => String(candidate.movementId) === selectedId) ?? valid.at(-1)

  if (movement === undefined) {
    return <p className="rounded bg-veil p-3">Aucun mouvement valable à corriger.</p>
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (movement === undefined) {
      return
    }
    const data = new FormData(event.currentTarget)
    const text = (name: string) => String(data.get(name) ?? '')
    const reasonCode = text('reasonCode')
    const reasonComment = text('reasonComment')
    const before = {
      stationCode: movement.stationCode,
      quantityKg: movement.quantityKg,
      occurredAt: movement.occurredAt,
    }

    onStart()
    if (action === 'replace') {
      // What was typed is sent as it is: if the API refuses it, it says why.
      const replacement = {
        stationCode: text('stationCode'),
        quantityKg: Number(text('quantityKg')),
        occurredAt: toUtcText(text('occurredAt')),
        reasonCode,
        reasonComment,
      }
      if (await submit(() => replaceMovement(batchCode, movement.movementId, replacement))) {
        onCorrected({
          kind: 'REPLACE',
          batchCode,
          movementType: movement.movementType,
          before,
          after: {
            stationCode: replacement.stationCode,
            quantityKg: replacement.quantityKg,
            occurredAt: replacement.occurredAt,
          },
          reasonCode,
          reasonComment,
        })
      }
    } else if (await submit(() => cancelMovement(batchCode, movement.movementId, { reasonCode, reasonComment }))) {
      onCorrected({ kind: 'CANCEL', batchCode, movementType: movement.movementType, before, reasonCode, reasonComment })
    }
  }

  return (
    <form
      onSubmit={handleSubmit}
      className="flex max-w-md flex-col gap-3 rounded border border-edge-strong bg-paper p-4 shadow-sm"
    >
      {state.status === 'error' && <FormAlert error={state.error} fieldNames={FIELD_NAMES} />}

      <Field label="Mouvement à corriger">
        <select value={selectedId} onChange={(event) => setSelectedId(event.target.value)} className={FIELD}>
          {valid.map((candidate) => (
            <option key={candidate.movementId} value={String(candidate.movementId)}>
              {`${movementLabel(candidate.movementType)} · ${formatKg(candidate.quantityKg)} · ${formatUtc(candidate.occurredAt)}`}
            </option>
          ))}
        </select>
      </Field>

      <Field label="Que faire ?">
        <select value={action} onChange={(event) => setAction(event.target.value as Action)} className={FIELD}>
          <option value="replace">Remplacer les valeurs</option>
          <option value="cancel">Annuler le mouvement (il n'a pas eu lieu)</option>
        </select>
      </Field>

      {action === 'replace' ? (
        <>
          <Field label="Code de la station" messages={fieldMessages.stationCode}>
            <input
              key={`station-${movement.movementId}`}
              name="stationCode"
              required
              maxLength={20}
              defaultValue={movement.stationCode}
              className={`${FIELD} font-mono`}
            />
          </Field>
          <Field label="Quantité (kg)" messages={fieldMessages.quantityKg}>
            <input
              key={`quantity-${movement.movementId}`}
              name="quantityKg"
              type="number"
              step="0.01"
              required
              defaultValue={movement.quantityKg}
              className={FIELD}
            />
          </Field>
          <Field label="Date et heure (UTC)" messages={fieldMessages.occurredAt}>
            <input
              key={`time-${movement.movementId}`}
              name="occurredAt"
              type="datetime-local"
              step="1"
              required
              defaultValue={toInputTime(movement.occurredAt)}
              className={FIELD}
            />
          </Field>
        </>
      ) : (
        <p className="rounded bg-veil p-3 text-sm">
          Seul le dernier mouvement valable d'un lot peut être annulé, jamais sa réception. Le lot revient à l'étape
          d'avant.
        </p>
      )}

      <Field label="Motif" messages={fieldMessages.reasonCode}>
        <select name="reasonCode" defaultValue="DATA_ENTRY_ERROR" className={FIELD}>
          {REASON_CODES.map((code) => (
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
        {sending ? 'Envoi…' : action === 'replace' ? 'Enregistrer la correction' : 'Annuler le mouvement'}
      </button>
    </form>
  )
}
