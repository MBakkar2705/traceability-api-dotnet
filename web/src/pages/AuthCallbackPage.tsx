import { useEffect, useRef, useState } from 'react'
import { Link, useNavigate } from 'react-router'
import { getUserManager } from '../auth/userManager'
import AuthScreen from '../components/AuthScreen'
import Loading from '../components/Loading'

// Where Keycloak sends the user back after the sign-in. The address carries a one-time code that
// the library exchanges for the tokens; then the user goes to the home page.
export default function AuthCallbackPage() {
  const navigate = useNavigate()
  const [failed, setFailed] = useState(false)
  // In development, React runs an effect twice, and the code can be used only once.
  const started = useRef(false)

  useEffect(() => {
    if (started.current) {
      return
    }
    started.current = true
    getUserManager()
      .signinRedirectCallback()
      .then(
        () => navigate('/', { replace: true }),
        () => setFailed(true),
      )
  }, [navigate])

  return (
    <AuthScreen>
      {failed ? (
        <div role="alert" className="rounded border border-red-200 bg-red-50 p-4 text-red-800">
          <p className="font-medium">La connexion a échoué.</p>
          <p className="mt-1">
            <Link to="/" className="text-link underline">
              Retour à l'accueil
            </Link>
          </p>
        </div>
      ) : (
        <Loading hint="Connexion en cours." />
      )}
    </AuthScreen>
  )
}
