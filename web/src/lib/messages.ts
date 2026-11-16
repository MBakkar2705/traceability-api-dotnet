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
  50103: "Ce mouvement n'appartient pas à ce lot.",
  // Lot 12b: the batch was written with a code that is no longer its current code.
  50104: 'Ce code est un ancien code de lot : utilisez le code actuel.',
  // Already exists (writes).
  50200: 'Une ferme porte déjà ce code.',
  50201: 'Une station porte déjà ce code.',
  50202: 'Un lot porte déjà ce code.',
  // Two meanings: a station already has the function, or (lot 12b) a code is the old code of another
  // batch. This general text fits both; each form gives its own (see CodeMessages).
  50203: 'Ce code ou cette fonction existe déjà.',
  // A business rule is broken (writes).
  50300: "Ce lot est déjà expédié : aucun mouvement n'est plus possible.",
  50301: "Ce mouvement n'est pas l'étape suivante du lot.",
  50302: 'La quantité dépasse la quantité actuelle du lot.',
  50303: "Cette station n'a pas la fonction de ce mouvement.",
  // Corrections (lot 12a).
  50304: "La quantité ne peut pas dépasser celle de l'étape précédente, ni être inférieure à celle de l'étape suivante.",
  50305: 'Ce mouvement est annulé : il ne peut plus être corrigé.',
  50306: "Seul le dernier mouvement valable d'un lot peut être annulé.",
  50307: "La réception d'un lot ne peut pas être annulée.",
  50308: 'Les nouvelles valeurs sont identiques aux valeurs actuelles : rien à corriger.',
  // Lot 12b: the harvest day and the reception day of a batch (both ways: a harvest after the
  // reception, or a reception moved before the harvest).
  50309: 'La date de récolte ne peut pas être après le jour de la réception.',
  // A value is not valid.
  50400: 'Le code ne peut pas être vide.',
  50401: 'La quantité doit être supérieure à 0.',
  50402: 'Type de mouvement inconnu.',
  50403: 'Statut inconnu.',
  50404: 'Numéro ou taille de page invalide.',
  50405: "L'auteur de la correction n'est pas connu.",
  50406: "L'identifiant ou le nom de l'auteur est trop long.",
  50407: 'Motif inconnu.',
  50408: 'Le motif « Autre » demande un commentaire.',
  50409: 'Le commentaire est trop long (500 caractères au plus).',
}

// The texts that ONE form gives to some error codes, instead of the general ones above (lot 12b).
// The code 50203 means "this station already has this function" for a station and "this code is the
// old code of another batch" for a batch: the general text cannot say both exactly.
export type CodeMessages = Record<number, string>

function messageForCode(errorCode: number | undefined, own: CodeMessages): string | undefined {
  if (errorCode === undefined) {
    return undefined
  }
  if (Object.hasOwn(own, errorCode)) {
    return own[errorCode]
  }
  return Object.hasOwn(MESSAGE_BY_CODE, errorCode) ? MESSAGE_BY_CODE[errorCode] : undefined
}

export function describeError(error: unknown, own: CodeMessages = {}): ErrorMessage {
  if (error instanceof NetworkError) {
    return { message: "Impossible de joindre l'API. Est-elle lancée ?" }
  }

  if (error instanceof ApiError) {
    const byCode = messageForCode(error.errorCode, own)
    if (byCode) {
      return { message: byCode }
    }
    if (error.status === 400) {
      return { message: 'Adresse ou filtre invalide.' }
    }
    if (error.status === 401) {
      return { message: "Vous n'êtes pas connecté, ou votre session a expiré. Rechargez la page pour vous reconnecter." }
    }
    if (error.status === 403) {
      return { message: "Vous n'avez pas le droit de faire cela." }
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

export function describeWriteError(error: unknown, own: CodeMessages = {}): WriteErrorMessage {
  if (error instanceof NetworkError) {
    // The request may have reached the API: with no answer, we cannot know if the data was saved.
    return {
      message:
        "Pas de réponse de l'API : l'enregistrement a peut-être eu lieu. Vérifiez dans la liste avant de recommencer.",
      fieldMessages: {},
    }
  }

  if (error instanceof ApiError && error.status === 400) {
    if (messageForCode(error.errorCode, own) === undefined) {
      const fieldMessages = translateFieldErrors(error.fieldErrors)
      const hasFields = Object.keys(fieldMessages).length > 0
      return { message: hasFields ? 'Certains champs sont invalides.' : 'Requête invalide.', fieldMessages }
    }
  }

  return { ...describeError(error, own), fieldMessages: {} }
}
