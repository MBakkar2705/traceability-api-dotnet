import type { ReactNode } from 'react'

// A card with label / value pairs (the details of a station or of a batch).
export default function DetailCard({ fields }: { fields: { label: string; value: ReactNode }[] }) {
  return (
    <dl className="grid w-fit max-w-full grid-cols-[auto_1fr] gap-x-8 gap-y-2 rounded border border-edge-strong bg-paper p-4 shadow-sm md:min-w-[44rem]">
      {fields.map((field) => (
        <div key={field.label} className="contents">
          <dt className="text-ink-soft">{field.label}</dt>
          <dd className="font-medium">{field.value}</dd>
        </div>
      ))}
    </dl>
  )
}
