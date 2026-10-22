import { Navigate, Route, Routes } from 'react-router'
import Layout from './components/Layout'
import BatchesPage from './pages/BatchesPage'
import BatchPage from './pages/BatchPage'
import FarmsPage from './pages/FarmsPage'
import NewBatchPage from './pages/NewBatchPage'
import NewFarmPage from './pages/NewFarmPage'
import NewStationPage from './pages/NewStationPage'
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
        <Route path="new-batch" element={<NewBatchPage />} />
        <Route path="new-farm" element={<NewFarmPage />} />
        <Route path="stations" element={<StationsPage />} />
        <Route path="new-station" element={<NewStationPage />} />
        <Route path="stations/:stationCode" element={<StationPage />} />
        <Route path="*" element={<NotFoundPage />} />
      </Route>
    </Routes>
  )
}
