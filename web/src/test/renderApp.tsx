import { render } from '@testing-library/react'
import { MemoryRouter } from 'react-router'
import App from '../App'

// The whole application, as if the browser were at this address.
export function renderApp(url: string) {
  return render(
    <MemoryRouter initialEntries={[url]}>
      <App />
    </MemoryRouter>,
  )
}
