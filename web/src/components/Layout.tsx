import { NavLink, Outlet } from 'react-router'
import { useAuth } from '../auth/AuthContext'
import Decoration from './Decoration'

const LINKS = [
  { to: '/batches', label: 'Lots' },
  { to: '/farms', label: 'Fermes' },
  { to: '/stations', label: 'Stations' },
]

export default function Layout() {
  const { state, signOut } = useAuth()

  return (
    <div className="min-h-screen bg-page text-base text-ink">
      <Decoration />
      <header className="relative z-10 bg-nav text-white">
        <nav className="mx-auto flex max-w-4xl flex-wrap items-center gap-2 px-4 py-3">
          <span className="mr-4 text-lg font-semibold">Traçabilité</span>
          {LINKS.map((link) => (
            <NavLink
              key={link.to}
              to={link.to}
              className={({ isActive }) =>
                `rounded px-3 py-2 ${isActive ? 'bg-nav-active text-white' : 'text-stone-200 hover:bg-nav-hover'}`
              }
            >
              {link.label}
            </NavLink>
          ))}
          {state.status === 'signedIn' && (
            <div className="ml-auto flex flex-wrap items-center gap-2">
              <span className="text-stone-200">{state.userName}</span>
              <button type="button" onClick={signOut} className="rounded px-3 py-2 text-stone-200 hover:bg-nav-hover">
                Se déconnecter
              </button>
            </div>
          )}
        </nav>
      </header>
      <main className="relative z-10 mx-auto max-w-4xl px-4 py-4">
        <Outlet />
      </main>
    </div>
  )
}
