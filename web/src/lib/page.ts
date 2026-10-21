// The page number is kept in the address (?page=3). Anything that is not a whole number from 1
// (missing, text, 0, negative) means page 1.
export function readPageNumber(value: string | null): number {
  if (value === null || !/^\d+$/.test(value)) {
    return 1
  }
  const number = Number(value)
  return Number.isSafeInteger(number) && number >= 1 ? number : 1
}
