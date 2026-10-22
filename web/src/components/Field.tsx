import type { ReactNode } from 'react'

interface FieldProps {
  label: string
  // The messages of the API about this field, already in French.
  messages?: string[]
  // The field itself (an input, a select...).
  children: ReactNode
}

// A field of a form: its label, the field, and under it the messages about it. The same message
// said twice (two unknown texts both become "Valeur invalide.") is shown once.
export default function Field({ label, messages, children }: FieldProps) {
  return (
    <div className="flex flex-col gap-1">
      <label className="flex flex-col gap-1">
        <span className="text-sm text-ink-soft">{label}</span>
        {children}
      </label>
      {[...new Set(messages)].map((message) => (
        <p key={message} className="text-sm text-red-800">
          {message}
        </p>
      ))}
    </div>
  )
}
