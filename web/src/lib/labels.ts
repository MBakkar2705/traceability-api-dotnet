// French labels of the values the API sends in English. A value we do not know is shown as it is,
// so that a surprise stays visible.

const STATUS_LABELS: Record<string, string> = {
  RECEIVED: 'Reçu',
  SORTED: 'Trié',
  PACKED: 'Emballé',
  SHIPPED: 'Expédié',
}

const MOVEMENT_LABELS: Record<string, string> = {
  RECEPTION: 'Réception',
  SORTING: 'Tri',
  PACKING: 'Emballage',
  SHIPMENT: 'Expédition',
}

// The reasons of a correction (lot 12a) and the two kinds of correction.
const REASON_LABELS: Record<string, string> = {
  DATA_ENTRY_ERROR: 'Erreur de saisie',
  MEASUREMENT_ERROR: 'Erreur de mesure',
  OTHER: 'Autre',
}

const CORRECTION_KIND_LABELS: Record<string, string> = {
  REPLACE: 'Valeurs remplacées',
  CANCEL: 'Mouvement annulé',
}

// The author written by the migration of lot 11 in the movements that existed before it.
const AUTHOR_LABELS: Record<string, string> = {
  Initial_User: 'Données initiales',
}

function label(labels: Record<string, string>, value: string): string {
  return Object.hasOwn(labels, value) ? labels[value] : value
}

export const statusLabel = (value: string): string => label(STATUS_LABELS, value)

export const movementLabel = (value: string): string => label(MOVEMENT_LABELS, value)

export const authorLabel = (value: string): string => label(AUTHOR_LABELS, value)

export const reasonLabel = (value: string): string => label(REASON_LABELS, value)

export const correctionKindLabel = (value: string): string => label(CORRECTION_KIND_LABELS, value)
