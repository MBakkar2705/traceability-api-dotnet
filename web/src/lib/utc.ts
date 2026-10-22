// Helpers for the "date and time" fields of the forms. The user types a time in UTC, and the API
// wants it written with a Z at the end.

const DATE_TIME_FIELD = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?$/

// The value of an <input type="datetime-local"> -> the text the API wants:
// "2026-10-14T06:00" -> "2026-10-14T06:00:00Z". Anything else is returned unchanged: an empty value
// stays empty (the API says that the field is required) and a surprise stays visible instead of
// being guessed.
export function toUtcText(value: string): string {
  const match = DATE_TIME_FIELD.exec(value)
  if (!match) {
    return value
  }
  return match[1] === undefined ? `${value}:00Z` : `${value}Z`
}

// The current time in UTC, written like the value of an <input type="datetime-local"> (no seconds).
// toISOString always writes UTC, so the time zone of the machine never shifts the value. `now` can
// be given so that a test does not depend on the clock.
export function nowUtcInput(now: Date = new Date()): string {
  return now.toISOString().slice(0, 16)
}
