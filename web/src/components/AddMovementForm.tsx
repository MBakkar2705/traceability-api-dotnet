import { useState } from 'react'
import type { FormEvent } from 'react'
import { addMovement } from '../api/client'
import { MOVEMENT_TYPES } from '../api/types'
import { movementLabel } from '../lib/labels'
import { nextMovementType } from '../lib/nextStep'
import { useSubmit } from '../lib/useSubmit'
import { nowUtcInput, toUtcText } from '../lib/utc'
import Field from './Field'
import FormAlert from './FormAlert'
import { BUTTON, FIELD } from './styles'

// The names of the fields in the API (and of the inputs).
const FIELD_NAMES = ['stationCode', 'movementType', 'quantityKg', 'occurredAt']

interface AddMovementFormProps {
  batchCode: string
  // The status and the quantity of the batch now: they decide what the form proposes.
  status: string
  quantityKg: number
  // Called when the movement has been added: the page reads the batch again.
  onAdded: (movementType: string) => void
}

// The form that adds a movement to a batch. The page gives it a `key` that changes with the status
// of the batch, so that it starts again (next step, new quantity, new time) after each movement.
export default function AddMovementForm({ batchCode, status, quantityKg, onAdded }: AddMovementFormProps) {
  const { state, submit } = useSubmit()
  // The time of the movement starts at the current time (UTC), read once when the form appears.
  const [now] = useState(nowUtcInput)
  const fieldMessages = state.status === 'error' ? state.error.fieldMessages : {}
  const sending = state.status === 'sending'

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const data = new FormData(event.currentTarget)
    const text = (name: string) => String(data.get(name) ?? '')
    // What was typed is sent as it is: if the API refuses it, it says why. Only the form of two
    // values changes: the quantity becomes a number, and the time gets the Z of UTC.
    const movement = {
      stationCode: text('stationCode'),
      movementType: text('movementType'),
      quantityKg: Number(text('quantityKg')),
      occurredAt: toUtcText(text('occurredAt')),
    }

    if (await submit(() => addMovement(batchCode, movement))) {
      onAdded(movement.movementType)
    }
  }

  return (
    <form
      onSubmit={handleSubmit}
      className="flex max-w-md flex-col gap-3 rounded border border-edge-strong bg-paper p-4 shadow-sm"
    >
      {state.status === 'error' && <FormAlert error={state.error} fieldNames={FIELD_NAMES} />}

      <Field label="Type de mouvement" messages={fieldMessages.movementType}>
        <select name="movementType" defaultValue={nextMovementType(status)} className={FIELD}>
          {MOVEMENT_TYPES.map((type) => (
            <option key={type} value={type}>
              {movementLabel(type)}
            </option>
          ))}
        </select>
      </Field>
      <Field label="Code de la station" messages={fieldMessages.stationCode}>
        <input name="stationCode" required maxLength={20} className={`${FIELD} font-mono`} />
      </Field>
      <Field label="Quantité (kg)" messages={fieldMessages.quantityKg}>
        <input name="quantityKg" type="number" step="0.01" required defaultValue={quantityKg} className={FIELD} />
      </Field>
      <Field label="Date et heure (UTC)" messages={fieldMessages.occurredAt}>
        <input name="occurredAt" type="datetime-local" required defaultValue={now} className={FIELD} />
      </Field>

      <button type="submit" disabled={sending} className={BUTTON}>
        {sending ? 'Envoi…' : 'Ajouter le mouvement'}
      </button>
    </form>
  )
}
