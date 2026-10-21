// @vitest-environment jsdom

import { cleanup, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it } from 'vitest'
import Pagination from './Pagination'

afterEach(cleanup)

const THIN_SPACE = '\u202f' // the French thousands separator, a narrow no-break space

describe('Pagination', () => {
  it('writes the page, the number of pages and the total in the French way', () => {
    render(<Pagination pageNumber={1234} pageSize={15} totalCount={1000000} onPageChange={() => {}} />)

    const text = screen.getByRole('navigation', { name: 'Pagination' }).textContent ?? ''
    expect(text).toContain(`Page 1${THIN_SPACE}234 sur 66${THIN_SPACE}667`)
    expect(text).toContain(`1${THIN_SPACE}000${THIN_SPACE}000 au total`)
  })

  it('has one page when there is nothing', () => {
    render(<Pagination pageNumber={1} pageSize={15} totalCount={0} onPageChange={() => {}} />)

    expect(screen.getByText(/Page 1 sur 1/)).toBeTruthy()
  })
})
