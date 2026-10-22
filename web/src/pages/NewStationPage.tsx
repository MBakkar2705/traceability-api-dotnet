import type { FormEvent } from 'react'
import { useNavigate } from 'react-router'
import { createStation } from '../api/client'
import BackLink from '../components/BackLink'
import Field from '../components/Field'
import FormAlert from '../components/FormAlert'
import PageTitle from '../components/PageTitle'
import { BUTTON, FIELD } from '../components/styles'
import { useSubmit } from '../lib/useSubmit'

// The names of the fields in the API (and of the inputs).
const FIELD_NAMES = ['code', 'name']

export default function NewStationPage() {
  const { state, submit } = useSubmit()
  const navigate = useNavigate()
  const fieldMessages = state.status === 'error' ? state.error.fieldMessages : {}
  const sending = state.status === 'sending'

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    // Read now: the form is no longer the target of the event once the call has been awaited.
    const data = new FormData(event.currentTarget)
    // What was typed is sent as it is: if the API refuses it, it says why.
    const station = {
      code: String(data.get('code') ?? ''),
      name: String(data.get('name') ?? ''),
    }

    if (await submit(() => createStation(station))) {
      navigate(`/stations/${encodeURIComponent(station.code)}`)
    }
  }

  return (
    <section>
      <BackLink to="/stations">Retour aux stations</BackLink>
      <PageTitle>Nouvelle station</PageTitle>

      <form
        onSubmit={handleSubmit}
        className="flex max-w-md flex-col gap-3 rounded border border-edge-strong bg-paper p-4 shadow-sm"
      >
        {state.status === 'error' && <FormAlert error={state.error} fieldNames={FIELD_NAMES} />}

        <Field label="Code" messages={fieldMessages.code}>
          <input name="code" required maxLength={20} className={`${FIELD} font-mono`} />
        </Field>
        <Field label="Nom" messages={fieldMessages.name}>
          <input name="name" required maxLength={100} className={FIELD} />
        </Field>

        <button type="submit" disabled={sending} className={BUTTON}>
          {sending ? 'Envoi…' : 'Créer la station'}
        </button>
      </form>
    </section>
  )
}
