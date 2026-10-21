export default function Loading({ hint }: { hint?: string }) {
  return (
    <div role="status" className="inline-block rounded bg-veil px-4 py-2 text-ink-soft">
      <p>Chargement…</p>
      {hint && <p className="text-sm">{hint}</p>}
    </div>
  )
}
