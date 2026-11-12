// @vitest-environment jsdom

import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import RecipientMessage from './RecipientMessage'

afterEach(() => {
  cleanup()
  vi.unstubAllGlobals()
})

describe('RecipientMessage', () => {
  it('shows the text to forward, and says that the application does not send it', () => {
    render(<RecipientMessage message="Bonjour, le lot est corrigé." />)

    expect((screen.getByLabelText('Message au destinataire') as HTMLTextAreaElement).value).toBe(
      'Bonjour, le lot est corrigé.',
    )
    expect(screen.getByText(/L'application ne l'envoie pas/)).toBeTruthy()
  })

  it('copies the text to the clipboard and says so', async () => {
    const writeText = vi.fn().mockResolvedValue(undefined)
    vi.stubGlobal('navigator', { clipboard: { writeText } })
    render(<RecipientMessage message="Le texte" />)

    fireEvent.click(screen.getByRole('button', { name: 'Copier le message' }))

    expect(await screen.findByText('Message copié.')).toBeTruthy()
    expect(writeText).toHaveBeenCalledWith('Le texte')
  })

  it('says so when the copy is not possible, and the text stays there to be copied by hand', async () => {
    vi.stubGlobal('navigator', { clipboard: { writeText: vi.fn().mockRejectedValue(new Error('denied')) } })
    render(<RecipientMessage message="Le texte" />)

    fireEvent.click(screen.getByRole('button', { name: 'Copier le message' }))

    expect(await screen.findByText(/Copie impossible/)).toBeTruthy()
    expect((screen.getByLabelText('Message au destinataire') as HTMLTextAreaElement).value).toBe('Le texte')
  })
})
