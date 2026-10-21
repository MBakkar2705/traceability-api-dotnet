import { Navigate, Route, Routes } from 'react-router'
import Layout from './components/Layout'
import BatchesPage from './pages/BatchesPage'
import BatchPage from './pages/BatchPage'
import FarmsPage from './pages/FarmsPage'
import NotFoundPage from './pages/NotFoundPage'
import StationPage from './pages/StationPage'
import StationsPage from './pages/StationsPage'

export default function App() {
  return (
    <Routes>
      <Route element={<Layout />}>
        <Route index element={<Navigate to="/batches" replace />} />
        <Route path="batches" element={<BatchesPage />} />
        <Route path="batches/:batchCode" element={<BatchPage />} />
        <Route path="farms" element={<FarmsPage />} />
        <Route path="stations" element={<StationsPage />} />
        <Route path="stations/:stationCode" element={<StationPage />} />
        <Route path="*" element={<NotFoundPage />} />
      </Route>
    </Routes>
  )
}
