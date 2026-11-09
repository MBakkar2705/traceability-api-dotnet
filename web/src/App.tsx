import type { ReactNode } from 'react'
import { Navigate, Route, Routes } from 'react-router'
import RequireSignIn from './auth/RequireSignIn'
import Layout from './components/Layout'
import WriterOnly from './components/WriterOnly'
import AuthCallbackPage from './pages/AuthCallbackPage'
import BatchesPage from './pages/BatchesPage'
import BatchPage from './pages/BatchPage'
import FarmsPage from './pages/FarmsPage'
import NewBatchPage from './pages/NewBatchPage'
import NewFarmPage from './pages/NewFarmPage'
import NewStationPage from './pages/NewStationPage'
import NotFoundPage from './pages/NotFoundPage'
import StationPage from './pages/StationPage'
import StationsPage from './pages/StationsPage'

// A page that writes: a user who cannot write gets this message instead of the form (lot 10c).
function WriterPage({ children }: { children: ReactNode }) {
  return (
    <WriterOnly fallback={<p className="rounded bg-veil p-3">Vous n'avez pas le droit de saisir des données.</p>}>
      {children}
    </WriterOnly>
  )
}

export default function App() {
  return (
    <Routes>
      {/* Where Keycloak sends the user back: it must open before anyone is signed in. */}
      <Route path="auth/callback" element={<AuthCallbackPage />} />
      <Route element={<RequireSignIn />}>
        <Route element={<Layout />}>
          <Route index element={<Navigate to="/batches" replace />} />
          <Route path="batches" element={<BatchesPage />} />
          <Route path="batches/:batchCode" element={<BatchPage />} />
          <Route path="farms" element={<FarmsPage />} />
          <Route
            path="new-batch"
            element={
              <WriterPage>
                <NewBatchPage />
              </WriterPage>
            }
          />
          <Route
            path="new-farm"
            element={
              <WriterPage>
                <NewFarmPage />
              </WriterPage>
            }
          />
          <Route path="stations" element={<StationsPage />} />
          <Route
            path="new-station"
            element={
              <WriterPage>
                <NewStationPage />
              </WriterPage>
            }
          />
          <Route path="stations/:stationCode" element={<StationPage />} />
          <Route path="*" element={<NotFoundPage />} />
        </Route>
      </Route>
    </Routes>
  )
}
