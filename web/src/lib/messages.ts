// What the user reads when a call to the API fails, for a read (describeError) or for a write
// (describeWriteError). The texts are in French; the English texts of the API (the "detail" of
// an error) are not shown to the user.

import { ApiError, NetworkError } from '../api/errors'

export interface ErrorMessage {
  message: string
  // Shown in small for unexpected errors, so the error can be found in the log of the API.
  traceId?: string
}

// Errors the screens can get (the stored procedures raise these numbers).
const MESSAGE_BY_CODE: Record<number, string> = {
  // Not found (reads and writes).
  50100: 'Lot introuvable.',
  50101: 'Ferme introuvable.',
  50102: 'Station introuvable.',
  // Already exists (writes).
  50200: 'Une ferme porte déjà ce code.',
  50201: 'Une station porte déjà ce code.',
  50202: 'Un lot porte déjà ce code.',
  50203: 'Cette station a déjà cette fonction.',
  // A business rule is broken (writes).
  50300: "Ce lot est déjà expédié : aucun mouvement n'est plus possible.",
  50301: "Ce mouvement n'est pas l'étape suivante du lot.",
  50302: 'La quantité dépasse la quantité actuelle du lot.',
  50303: "Cette station n'a pas la fonction de ce mouvement.",
  // A value is not valid.
  50400: 'Le code ne peut pas être vide.',
  50401: 'La quantité doit être supérieure à 0.',
  50402: 'Type de mouvement inconnu.',
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

// A form (a write) also needs the messages of each field when the API refuses the shape of the
// request (400 with no error code).
export interface WriteErrorMessage extends ErrorMessage {
  fieldMessages: Record<string, string[]>
}

// The English texts of the API for a field (src/Traceability.Api/Validation/FieldErrors.cs), copied
// by hand. A text that matches none of them is shown as "Valeur invalide.". If a text changes in
// the API, the unit test FieldErrorsTests.The_texts_read_by_the_web_interface_do_not_change fails:
// change the matching line here and in messages.test.ts.
const FIELD_MESSAGES: Array<[RegExp, (match: RegExpExecArray) => string]> = [
  [/^The field is required\.$/, () => 'Champ obligatoire.'],
  [
    /^Only letters A-Z, digits, '-' and '_' are allowed, up to (\d+) characters\.$/,
    (match) => `Lettres A-Z sans accent, chiffres, « - » et « _ » seulement, ${match[1]} caractères au plus.`,
  ],
  [/^At most (\d+) characters are allowed\.$/, (match) => `${match[1]} caractères au plus.`],
  [/^At most (\d+) decimals are allowed\.$/, (match) => `${match[1]} décimales au plus.`],
  [
    /^The absolute value of the quantity is limited to ([\d.]+)\.$/,
    (match) => `La quantité ne peut pas dépasser ${match[1]} kg.`,
  ],
  [/^The time must end with 'Z' \(UTC\) or carry an offset/, () => "L'heure doit finir par « Z » (UTC) ou porter un décalage."],
]

function translateFieldMessage(message: string): string {
  for (const [pattern, translate] of FIELD_MESSAGES) {
    const match = pattern.exec(message)
    if (match) {
      return translate(match)
    }
  }
  return 'Valeur invalide.'
}

function translateFieldErrors(fieldErrors: Record<string, string[]> | undefined): Record<string, string[]> {
  const result: Record<string, string[]> = {}
  for (const [field, messages] of Object.entries(fieldErrors ?? {})) {
    result[field] = messages.map(translateFieldMessage)
  }
  return result
}

export function describeWriteError(error: unknown): WriteErrorMessage {
  if (error instanceof NetworkError) {
    // The request may have reached the API: with no answer, we cannot know if the data was saved.
    return {
      message:
        "Pas de réponse de l'API : l'enregistrement a peut-être eu lieu. Vérifiez dans la liste avant de recommencer.",
      fieldMessages: {},
    }
  }

  if (error instanceof ApiError && error.status === 400) {
    const knownCode = error.errorCode !== undefined && Object.hasOwn(MESSAGE_BY_CODE, error.errorCode)
    if (!knownCode) {
      const fieldMessages = translateFieldErrors(error.fieldErrors)
      const hasFields = Object.keys(fieldMessages).length > 0
      return { message: hasFields ? 'Certains champs sont invalides.' : 'Requête invalide.', fieldMessages }
    }
  }

  return { ...describeError(error), fieldMessages: {} }
}
