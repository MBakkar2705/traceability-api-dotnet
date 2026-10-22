// @vitest-environment jsdom

import { cleanup, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it } from 'vitest'
import type { WriteErrorMessage } from '../lib/messages'
import FormAlert from './FormAlert'

afterEach(cleanup)

function error(extra: Partial<WriteErrorMessage> = {}): WriteErrorMessage {
  return { message: 'Certains champs sont invalides.', fieldMessages: {}, ...extra }
}

describe('FormAlert', () => {
  it('shows the message in an alert, with the trace id of an unexpected error', () => {
    render(
      <FormAlert error={error({ message: 'Erreur inattendue du serveur.', traceId: '00-abc' })} fieldNames={['code']} />,
    )

    const alert = screen.getByRole('alert')
    expect(alert.textContent).toContain('Erreur inattendue du serveur.')
    expect(alert.textContent).toContain('Référence : 00-abc')
  })

  it('does not repeat the messages of the fields that the form shows', () => {
    render(
      <FormAlert error={error({ fieldMessages: { code: ['Champ obligatoire.'] } })} fieldNames={['code', 'name']} />,
    )

    expect(screen.queryByText('Champ obligatoire.')).toBeNull()
  })

  it('shows the messages of a field that the form does not have, so that none is lost', () => {
    render(
      <FormAlert error={error({ fieldMessages: { batchCode: ['Champ obligatoire.'] } })} fieldNames={['stationCode']} />,
    )

    expect(screen.getByText('Champ obligatoire.')).toBeTruthy()
  })
})
