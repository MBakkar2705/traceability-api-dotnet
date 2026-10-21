// What the user reads when a call to the API fails. The texts are in French; the English
// texts of the API (the "detail" of an error) are not shown to the user.

import { ApiError, NetworkError } from '../api/errors'

export interface ErrorMessage {
  message: string
  // Shown in small for unexpected errors, so the error can be found in the log of the API.
  traceId?: string
}

// Errors a read screen can get (the stored procedures raise these numbers).
const MESSAGE_BY_CODE: Record<number, string> = {
  50100: 'Lot introuvable.',
  50101: 'Ferme introuvable.',
  50102: 'Station introuvable.',
  50403: 'Statut inconnu.',
  50404: 'Numéro ou taille de page invalide.',
}

export function describeError(error: unknown): ErrorMessage {
  if (error instanceof NetworkError) {
    return { message: "Impossible de joindre l'API. Est-elle lancée ?" }
  }

  if (error instanceof ApiError) {
    const byCode = error.errorCode === undefined ? undefined : MESSAGE_BY_CODE[error.errorCode]
    if (byCode) {
      return { message: byCode }
    }
    if (error.status === 400) {
      return { message: 'Adresse ou filtre invalide.' }
    }
    if (error.status === 404) {
      return { message: 'Élément introuvable.' }
    }
    if (error.status >= 500) {
      return { message: 'Erreur inattendue du serveur.', traceId: error.traceId }
    }
    return { message: `Erreur ${error.status}.`, traceId: error.traceId }
  }

  return { message: 'Erreur inattendue.' }
}
