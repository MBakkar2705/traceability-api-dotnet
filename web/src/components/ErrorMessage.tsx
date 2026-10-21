import { describeError } from '../lib/messages'

export default function ErrorMessage({ error }: { error: unknown }) {
  const { message, traceId } = describeError(error)

  return (
    <div role="alert" className="rounded border border-red-200 bg-red-50 p-4 text-red-800">
      <p className="font-medium">{message}</p>
      {traceId && <p className="mt-1 text-sm">Référence : {traceId}</p>}
    </div>
  )
}
