import { useCallback } from 'react'
import { useParams } from 'react-router'
import { getStation } from '../api/client'
import BackLink from '../components/BackLink'
import DetailCard from '../components/DetailCard'
import ErrorMessage from '../components/ErrorMessage'
import Loading from '../components/Loading'
import PageTitle from '../components/PageTitle'
import { movementLabel } from '../lib/labels'
import { useApi } from '../lib/useApi'

export default function StationPage() {
  const { stationCode = '' } = useParams()

  const load = useCallback((signal: AbortSignal) => getStation(stationCode, signal), [stationCode])
  const state = useApi(load)

  return (
    <section>
      <BackLink to="/stations">Retour aux stations</BackLink>
      <PageTitle>Station {stationCode}</PageTitle>

      {state.status === 'loading' && <Loading />}
      {state.status === 'error' && <ErrorMessage error={state.error} />}
      {state.status === 'success' && (
        <DetailCard
          fields={[
            { label: 'Code', value: <span className="font-mono">{state.data.code}</span> },
            { label: 'Nom', value: state.data.name },
            {
              label: 'Fonctions',
              value:
                state.data.capabilities.length === 0 ? (
                  'Aucune fonction déclarée.'
                ) : (
                  <span className="flex flex-wrap gap-2">
                    {state.data.capabilities.map((capability) => (
                      <span key={capability} className="rounded bg-paper-head px-2 py-0.5 text-sm">
                        {movementLabel(capability)}
                      </span>
                    ))}
                  </span>
                ),
            },
          ]}
        />
      )}
    </section>
  )
}
