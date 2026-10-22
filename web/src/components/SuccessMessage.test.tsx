// @vitest-environment jsdom

import { cleanup, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it } from 'vitest'
import SuccessMessage from './SuccessMessage'

afterEach(cleanup)

describe('SuccessMessage', () => {
  it('shows the text in a status area', () => {
    render(<SuccessMessage>Ferme F001 créée.</SuccessMessage>)

    expect(screen.getByRole('status').textContent).toBe('Ferme F001 créée.')
  })
})
