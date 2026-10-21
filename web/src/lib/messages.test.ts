import { describe, expect, it } from 'vitest'
import { ApiError, NetworkError } from '../api/errors'
import { describeError } from './messages'

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
