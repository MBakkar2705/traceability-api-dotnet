import type { WriteErrorMessage } from '../lib/messages'

interface FormAlertProps {
  error: WriteErrorMessage
  // The names (in the API) of the fields that the form shows: their messages are under the fields.
  fieldNames: string[]
}

// The error of a form, above the fields. The messages of a field that the form does not show (for
// example a code that is in the address of the route and not in a field) are listed here, so that
// no message is lost.
export default function FormAlert({ error, fieldNames }: FormAlertProps) {
  const others = new Set(
    Object.entries(error.fieldMessages)
      .filter(([field]) => !fieldNames.includes(field))
      .flatMap(([, messages]) => messages),
  )

  return (
    <div role="alert" className="rounded border border-red-200 bg-red-50 p-4 text-red-800">
      <p className="font-medium">{error.message}</p>
      {others.size > 0 && (
        <ul className="mt-1 list-disc pl-5 text-sm">
          {[...others].map((message) => (
            <li key={message}>{message}</li>
          ))}
        </ul>
      )}
      {error.traceId && <p className="mt-1 text-sm">Référence : {error.traceId}</p>}
    </div>
  )
}
