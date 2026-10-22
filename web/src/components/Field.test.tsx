// @vitest-environment jsdom

import { cleanup, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it } from 'vitest'
import Field from './Field'

afterEach(cleanup)

describe('Field', () => {
  it('links the label to the field it wraps', () => {
    render(
      <Field label="Code">
        <input name="code" />
      </Field>,
    )

    expect(screen.getByLabelText('Code').getAttribute('name')).toBe('code')
  })

  it('shows the messages of the field under it, and nothing when there are none', () => {
    const { rerender } = render(
      <Field label="Code" messages={['Champ obligatoire.', '20 caractères au plus.']}>
        <input name="code" />
      </Field>,
    )
    expect(screen.getByText('Champ obligatoire.')).toBeTruthy()
    expect(screen.getByText('20 caractères au plus.')).toBeTruthy()

    rerender(
      <Field label="Code">
        <input name="code" />
      </Field>,
    )

    expect(screen.queryByText('Champ obligatoire.')).toBeNull()
  })
})
