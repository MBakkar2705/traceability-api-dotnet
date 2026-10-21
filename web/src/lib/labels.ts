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

function label(labels: Record<string, string>, value: string): string {
  return Object.hasOwn(labels, value) ? labels[value] : value
}

export const statusLabel = (value: string): string => label(STATUS_LABELS, value)

export const movementLabel = (value: string): string => label(MOVEMENT_LABELS, value)
