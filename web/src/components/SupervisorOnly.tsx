import type { ReactNode } from 'react'
import { useAuth } from '../auth/AuthContext'
import { canCorrect } from '../auth/roles'

interface SupervisorOnlyProps {
  children: ReactNode
}

// Shows what corrects (a form) to a user who has the supervisor role, and hides it from the others.
// It is a comfort only: the API refuses a correction without the role (403) whatever this
// component does.
export default function SupervisorOnly({ children }: SupervisorOnlyProps) {
  const { state } = useAuth()
  return <>{state.status === 'signedIn' && canCorrect(state.roles) ? children : null}</>
}
