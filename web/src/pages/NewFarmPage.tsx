import { useState } from 'react'
import type { FormEvent } from 'react'
import { Link } from 'react-router'
import { createFarm } from '../api/client'
import BackLink from '../components/BackLink'
import Field from '../components/Field'
import FormAlert from '../components/FormAlert'
import PageTitle from '../components/PageTitle'
import { BUTTON, FIELD } from '../components/styles'
import SuccessMessage from '../components/SuccessMessage'
import { useSubmit } from '../lib/useSubmit'

// The names of the fields in the API (and of the inputs).
const FIELD_NAMES = ['code', 'name', 'region']

export default function NewFarmPage() {
  const { state, submit } = useSubmit()
  const [createdCode, setCreatedCode] = useState<string | null>(null)
  const fieldMessages = state.status === 'error' ? state.error.fieldMessages : {}
  const sending = state.status === 'sending'

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    // Read now: the form is no longer the target of the event once the call has been awaited.
    const form = event.currentTarget
    const data = new FormData(form)
    // What was typed is sent as it is: if the API refuses it, it says why.
    const farm = {
      code: String(data.get('code') ?? ''),
      name: String(data.get('name') ?? ''),
      region: String(data.get('region') ?? ''),
    }

    setCreatedCode(null)
    if (await submit(() => createFarm(farm))) {
      setCreatedCode(farm.code)
      form.reset()
    }
  }

  return (
    <section>
      <BackLink to="/farms">Retour aux fermes</BackLink>
      <PageTitle>Nouvelle ferme</PageTitle>

      <form
        onSubmit={handleSubmit}
        className="flex max-w-md flex-col gap-3 rounded border border-edge-strong bg-paper p-4 shadow-sm"
      >
        {createdCode !== null && (
          <SuccessMessage>
            Ferme {createdCode} créée.{' '}
            <Link to="/farms" className="text-link underline">
              Voir les fermes
            </Link>
          </SuccessMessage>
        )}
        {state.status === 'error' && <FormAlert error={state.error} fieldNames={FIELD_NAMES} />}

        <Field label="Code" messages={fieldMessages.code}>
          <input name="code" required maxLength={20} className={`${FIELD} font-mono`} />
        </Field>
        <Field label="Nom" messages={fieldMessages.name}>
          <input name="name" required maxLength={100} className={FIELD} />
        </Field>
        <Field label="Région" messages={fieldMessages.region}>
          <input name="region" required maxLength={100} className={FIELD} />
        </Field>

        <button type="submit" disabled={sending} className={BUTTON}>
          {sending ? 'Envoi…' : 'Créer la ferme'}
        </button>
      </form>
    </section>
  )
}
