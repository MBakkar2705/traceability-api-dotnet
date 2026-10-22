import { useState } from 'react'
import type { FormEvent } from 'react'
import { addCapability } from '../api/client'
import { MOVEMENT_TYPES } from '../api/types'
import { movementLabel } from '../lib/labels'
import { useSubmit } from '../lib/useSubmit'
import Field from './Field'
import FormAlert from './FormAlert'
import { BUTTON, FIELD } from './styles'
import SuccessMessage from './SuccessMessage'

// The names of the fields in the API (and of the inputs).
const FIELD_NAMES = ['movementType']

interface AddCapabilityFormProps {
  stationCode: string
  // Called when the function has been added: the page reads the station again.
  onAdded: () => void
}

// The form that adds a function (a movement type) to a station.
export default function AddCapabilityForm({ stationCode, onAdded }: AddCapabilityFormProps) {
  const { state, submit } = useSubmit()
  const [addedType, setAddedType] = useState<string | null>(null)
  const fieldMessages = state.status === 'error' ? state.error.fieldMessages : {}
  const sending = state.status === 'sending'

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const movementType = String(new FormData(event.currentTarget).get('movementType') ?? '')

    setAddedType(null)
    if (await submit(() => addCapability(stationCode, movementType))) {
      setAddedType(movementType)
      onAdded()
    }
  }

  return (
    <form
      onSubmit={handleSubmit}
      className="mt-4 flex max-w-md flex-col gap-3 rounded border border-edge-strong bg-paper p-4 shadow-sm"
    >
      {addedType !== null && <SuccessMessage>{`Fonction ${movementLabel(addedType)} ajoutée.`}</SuccessMessage>}
      {state.status === 'error' && <FormAlert error={state.error} fieldNames={FIELD_NAMES} />}

      <Field label="Fonction à ajouter" messages={fieldMessages.movementType}>
        <select name="movementType" className={FIELD}>
          {MOVEMENT_TYPES.map((type) => (
            <option key={type} value={type}>
              {movementLabel(type)}
            </option>
          ))}
        </select>
      </Field>

      <button type="submit" disabled={sending} className={BUTTON}>
        {sending ? 'Envoi…' : 'Ajouter la fonction'}
      </button>
    </form>
  )
}
