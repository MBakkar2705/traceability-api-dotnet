// The movement that follows each status of a batch. This copies the rule of the procedure
// trace.AddMovement (no step skipped, none repeated), only to propose the right step: it is the API
// that decides, and that refuses any other.
const NEXT_STEP: Record<string, string> = {
  RECEIVED: 'SORTING',
  SORTED: 'PACKING',
  PACKED: 'SHIPMENT',
}

// undefined after SHIPPED (nothing follows), and for a status that is not known.
export function nextMovementType(status: string): string | undefined {
  return Object.hasOwn(NEXT_STEP, status) ? NEXT_STEP[status] : undefined
}
