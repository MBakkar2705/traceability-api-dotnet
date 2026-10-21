import { Link } from 'react-router'
import PageTitle from '../components/PageTitle'

export default function NotFoundPage() {
  return (
    <section>
      <PageTitle>Page introuvable</PageTitle>
      <p className="rounded bg-veil p-3">
        Cette adresse ne correspond à aucun écran.{' '}
        <Link to="/" className="text-link underline">
          Retour à l'accueil
        </Link>
      </p>
    </section>
  )
}
