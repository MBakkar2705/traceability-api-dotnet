import { useAuth } from '../auth/AuthContext'
import type { SignedOutReason } from '../auth/AuthContext'
import AuthScreen from '../components/AuthScreen'
import PageTitle from '../components/PageTitle'
import { BUTTON } from '../components/styles'

// The sign-in screen: one button, which sends the user to Keycloak. It does not leave by itself,
// so a failure cannot loop.
export default function SignInPage({ reason }: { reason?: SignedOutReason }) {
  const { signIn } = useAuth()

  return (
    <AuthScreen>
      <PageTitle>Connexion</PageTitle>
      {reason === 'expired' && <p className="mb-3 rounded bg-veil p-3">Votre session a expiré. Connectez-vous de nouveau.</p>}
      {reason === 'unreachable' && (
        <div role="alert" className="mb-3 rounded border border-red-200 bg-red-50 p-4 text-red-800">
          Impossible de joindre le serveur de connexion. Est-il lancé ?
        </div>
      )}
      <p className="mb-3 rounded bg-veil p-3">Connectez-vous pour consulter et saisir les données de traçabilité.</p>
      <button type="button" onClick={signIn} className={BUTTON}>
        Se connecter
      </button>
    </AuthScreen>
  )
}
