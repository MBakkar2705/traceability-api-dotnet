import { Outlet } from 'react-router'
import AuthScreen from '../components/AuthScreen'
import Loading from '../components/Loading'
import SignInPage from '../pages/SignInPage'
import { useAuth } from './AuthContext'

// The screens inside it are shown only to a signed-in user; anyone else gets the sign-in screen.
export default function RequireSignIn() {
  const { state } = useAuth()

  if (state.status === 'loading') {
    return (
      <AuthScreen>
        <Loading />
      </AuthScreen>
    )
  }
  if (state.status === 'signedOut') {
    return <SignInPage reason={state.reason} />
  }
  return <Outlet />
}
