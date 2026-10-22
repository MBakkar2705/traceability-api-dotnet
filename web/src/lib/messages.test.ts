import { describe, expect, it } from 'vitest'
import { ApiError, NetworkError } from '../api/errors'
import { describeError, describeWriteError } from './messages'

describe('describeError', () => {
  it.each([
    [404, 50100, 'Lot introuvable.'],
    [404, 50101, 'Ferme introuvable.'],
    [404, 50102, 'Station introuvable.'],
    [400, 50403, 'Statut inconnu.'],
    [400, 50404, 'Numéro ou taille de page invalide.'],
  ])('says the error %i / %i in French', (status, errorCode, expected) => {
    expect(describeError(new ApiError({ status, errorCode })).message).toBe(expected)
  })

  it('falls back on the status when there is no error code (error of shape)', () => {
    expect(describeError(new ApiError({ status: 400 })).message).toBe('Adresse ou filtre invalide.')
    expect(describeError(new ApiError({ status: 404 })).message).toBe('Élément introuvable.')
  })

  it('falls back on the status when the error code is unknown', () => {
    expect(describeError(new ApiError({ status: 409, errorCode: 59999 })).message).toBe('Erreur 409.')
  })

  it('gives the trace id of an unexpected server error', () => {
    const result = describeError(new ApiError({ status: 500, traceId: '00-abc' }))

    expect(result).toEqual({ message: 'Erreur inattendue du serveur.', traceId: '00-abc' })
  })

  it('says when the API cannot be reached', () => {
    expect(describeError(new NetworkError()).message).toBe("Impossible de joindre l'API. Est-elle lancée ?")
  })

  it('has a message for anything else', () => {
    expect(describeError(new Error('boom')).message).toBe('Erreur inattendue.')
    expect(describeError('boom').message).toBe('Erreur inattendue.')
  })
})

describe('describeWriteError', () => {
  it.each([
    [404, 50100, 'Lot introuvable.'],
    [404, 50101, 'Ferme introuvable.'],
    [404, 50102, 'Station introuvable.'],
    [409, 50200, 'Une ferme porte déjà ce code.'],
    [409, 50201, 'Une station porte déjà ce code.'],
    [409, 50202, 'Un lot porte déjà ce code.'],
    [409, 50203, 'Cette station a déjà cette fonction.'],
    [422, 50300, "Ce lot est déjà expédié : aucun mouvement n'est plus possible."],
    [422, 50301, "Ce mouvement n'est pas l'étape suivante du lot."],
    [422, 50302, 'La quantité dépasse la quantité actuelle du lot.'],
    [422, 50303, "Cette station n'a pas la fonction de ce mouvement."],
    [400, 50400, 'Le code ne peut pas être vide.'],
    [400, 50401, 'La quantité doit être supérieure à 0.'],
    [400, 50402, 'Type de mouvement inconnu.'],
  ])('says the error %i / %i in French', (status, errorCode, expected) => {
    expect(describeWriteError(new ApiError({ status, errorCode })).message).toBe(expected)
  })

  // The English texts are copies of the ones of FieldErrors.cs (the API). This test cannot see a
  // change made in the API: the C# unit test FieldErrorsTests pins the same texts and fails first.
  it.each([
    ['The field is required.', 'Champ obligatoire.'],
    [
      "Only letters A-Z, digits, '-' and '_' are allowed, up to 20 characters.",
      'Lettres A-Z sans accent, chiffres, « - » et « _ » seulement, 20 caractères au plus.',
    ],
    ['At most 100 characters are allowed.', '100 caractères au plus.'],
    ['At most 2 decimals are allowed.', '2 décimales au plus.'],
    [
      'The absolute value of the quantity is limited to 99999999.99.',
      'La quantité ne peut pas dépasser 99999999.99 kg.',
    ],
    [
      "The time must end with 'Z' (UTC) or carry an offset, for example 2026-10-14T06:00:00Z.",
      "L'heure doit finir par « Z » (UTC) ou porter un décalage.",
    ],
    ['A text nobody planned.', 'Valeur invalide.'],
  ])('says the message of a field "%s" in French', (english, french) => {
    const result = describeWriteError(new ApiError({ status: 400, fieldErrors: { code: [english] } }))

    expect(result.message).toBe('Certains champs sont invalides.')
    expect(result.fieldMessages).toEqual({ code: [french] })
  })

  it('keeps every field with all its messages', () => {
    const fieldErrors = {
      code: ['The field is required.'],
      name: ['At most 100 characters are allowed.', 'A text nobody planned.'],
    }

    const result = describeWriteError(new ApiError({ status: 400, fieldErrors }))

    expect(result.fieldMessages).toEqual({
      code: ['Champ obligatoire.'],
      name: ['100 caractères au plus.', 'Valeur invalide.'],
    })
  })

  it('says "Requête invalide." for a 400 with neither an error code nor a field', () => {
    const result = describeWriteError(new ApiError({ status: 400 }))

    expect(result).toEqual({ message: 'Requête invalide.', fieldMessages: {} })
  })

  it('says that the data may have been saved when the API does not answer', () => {
    const result = describeWriteError(new NetworkError())

    expect(result.message).toBe(
      "Pas de réponse de l'API : l'enregistrement a peut-être eu lieu. Vérifiez dans la liste avant de recommencer.",
    )
  })

  it('gives the trace id of an unexpected server error', () => {
    const result = describeWriteError(new ApiError({ status: 500, traceId: '00-abc' }))

    expect(result).toEqual({ message: 'Erreur inattendue du serveur.', traceId: '00-abc', fieldMessages: {} })
  })

  it('falls back on the status when the error code is unknown', () => {
    expect(describeWriteError(new ApiError({ status: 409, errorCode: 59999 })).message).toBe('Erreur 409.')
  })

  it('has a message for anything else', () => {
    expect(describeWriteError(new Error('boom')).message).toBe('Erreur inattendue.')
  })
})
