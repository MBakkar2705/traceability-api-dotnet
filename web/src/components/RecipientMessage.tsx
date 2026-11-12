import { useState } from 'react'
import { BUTTON, FIELD } from './styles'

interface RecipientMessageProps {
  // The text to forward to the recipient (see lib/recipientMessage.ts).
  message: string
}

// Lot 12a: shown to the supervisor after a correction on a batch that was already shipped. The
// recipient may already have the old values. The application only offers the text: it does not send
// it, and does not record that anyone did.
export default function RecipientMessage({ message }: RecipientMessageProps) {
  const [copy, setCopy] = useState<'idle' | 'done' | 'failed'>('idle')

  async function handleCopy() {
    try {
      await navigator.clipboard.writeText(message)
      setCopy('done')
    } catch {
      setCopy('failed')
    }
  }

  return (
    <div className="mt-3 flex max-w-2xl flex-col gap-2 rounded border border-amber-300 bg-amber-50 p-4 text-amber-950">
      <p className="font-medium">Ce lot avait été expédié : prévenez le destinataire.</p>
      <p className="text-sm">
        Il a peut-être déjà reçu les anciennes valeurs. Copiez ce message et transmettez-le (le superviseur ou le
        commercial). L'application ne l'envoie pas et ne garde pas trace de l'envoi.
      </p>
      <textarea
        readOnly
        rows={9}
        value={message}
        aria-label="Message au destinataire"
        className={`${FIELD} font-mono text-sm`}
      />
      <div className="flex items-center gap-3">
        <button type="button" onClick={handleCopy} className={BUTTON}>
          Copier le message
        </button>
        {copy === 'done' && <span role="status">Message copié.</span>}
        {copy === 'failed' && (
          <span role="status">Copie impossible : sélectionnez le texte et copiez-le à la main.</span>
        )}
      </div>
    </div>
  )
}
