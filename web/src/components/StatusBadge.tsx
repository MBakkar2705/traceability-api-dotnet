import { statusLabel } from '../lib/labels'

const STYLES: Record<string, string> = {
  RECEIVED: 'bg-stone-200 text-stone-800',
  SORTED: 'bg-sky-100 text-sky-900',
  PACKED: 'bg-amber-100 text-amber-900',
  SHIPPED: 'bg-green-100 text-green-900',
}

export default function StatusBadge({ status }: { status: string }) {
  const style = Object.hasOwn(STYLES, status) ? STYLES[status] : STYLES.RECEIVED
  return <span className={`rounded-full px-2.5 py-0.5 text-sm font-medium ${style}`}>{statusLabel(status)}</span>
}
