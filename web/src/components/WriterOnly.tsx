import type { ReactNode } from 'react'
import { useAuth } from '../auth/AuthContext'
import { canWrite } from '../auth/roles'

interface WriterOnlyProps {
  children: ReactNode
  // Shown instead of the children to a user who cannot write. Nothing by default.
  fallback?: ReactNode
}

// Shows what writes (a button, a form) to a user who has the writer role, and hides it from the
// others. It is a comfort only: the API refuses a write without the role (403) whatever this
// component does.
export default function WriterOnly({ children, fallback = null }: WriterOnlyProps) {
  const { state } = useAuth()
  return <>{state.status === 'signedIn' && canWrite(state.roles) ? children : fallback}</>
}
