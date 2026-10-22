import { useState } from 'react'
import type { FormEvent } from 'react'
import { useNavigate } from 'react-router'
import { createBatch } from '../api/client'
import BackLink from '../components/BackLink'
import Field from '../components/Field'
import FormAlert from '../components/FormAlert'
import PageTitle from '../components/PageTitle'
import { BUTTON, FIELD } from '../components/styles'
import { nowUtcInput, toUtcText } from '../lib/utc'
import { useSubmit } from '../lib/useSubmit'

// The names of the fields in the API (and of the inputs).
const FIELD_NAMES = ['batchCode', 'farmCode', 'variety', 'harvestDate', 'quantityKg', 'stationCode', 'occurredAt']

export default function NewBatchPage() {
  const { state, submit } = useSubmit()
  const navigate = useNavigate()
  // The time of the reception starts at the current time (UTC), read once when the page opens.
  const [now] = useState(nowUtcInput)
  const fieldMessages = state.status === 'error' ? state.error.fieldMessages : {}
  const sending = state.status === 'sending'

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    // Read now: the form is no longer the target of the event once the call has been awaited.
    const data = new FormData(event.currentTarget)
    const text = (name: string) => String(data.get(name) ?? '')
    // What was typed is sent as it is: if the API refuses it, it says why. Only the form of two
    // values changes: the quantity becomes a number, and the time gets the Z of UTC.
    const batch = {
      batchCode: text('batchCode'),
      farmCode: text('farmCode'),
      variety: text('variety'),
      harvestDate: text('harvestDate'),
      quantityKg: Number(text('quantityKg')),
      stationCode: text('stationCode'),
      occurredAt: toUtcText(text('occurredAt')),
    }

    if (await submit(() => createBatch(batch))) {
      navigate(`/batches/${encodeURIComponent(batch.batchCode)}`)
    }
  }

  return (
    <section>
      <BackLink to="/batches">Retour aux lots</BackLink>
      <PageTitle>Nouveau lot</PageTitle>

      <form
        onSubmit={handleSubmit}
        className="flex max-w-md flex-col gap-3 rounded border border-edge-strong bg-paper p-4 shadow-sm"
      >
        {state.status === 'error' && <FormAlert error={state.error} fieldNames={FIELD_NAMES} />}

        <Field label="Code du lot" messages={fieldMessages.batchCode}>
          <input name="batchCode" required maxLength={20} className={`${FIELD} font-mono`} />
        </Field>
        <Field label="Code de la ferme" messages={fieldMessages.farmCode}>
          <input name="farmCode" required maxLength={20} className={`${FIELD} font-mono`} />
        </Field>
        <Field label="Variété" messages={fieldMessages.variety}>
          <input name="variety" required maxLength={100} className={FIELD} />
        </Field>
        <Field label="Date de récolte" messages={fieldMessages.harvestDate}>
          <input name="harvestDate" type="date" required className={FIELD} />
        </Field>
        <Field label="Quantité (kg)" messages={fieldMessages.quantityKg}>
          <input name="quantityKg" type="number" step="0.01" required className={FIELD} />
        </Field>
        <Field label="Code de la station" messages={fieldMessages.stationCode}>
          <input name="stationCode" required maxLength={20} className={`${FIELD} font-mono`} />
        </Field>
        <Field label="Date et heure de réception (UTC)" messages={fieldMessages.occurredAt}>
          <input name="occurredAt" type="datetime-local" required defaultValue={now} className={FIELD} />
        </Field>

        <button type="submit" disabled={sending} className={BUTTON}>
          {sending ? 'Envoi…' : 'Créer le lot'}
        </button>
      </form>
    </section>
  )
}
