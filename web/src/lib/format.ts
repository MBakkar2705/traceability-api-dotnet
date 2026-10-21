// Display formats. They work on the text sent by the API, without any Date object, so no
// time zone can ever shift a value: what the API stored in UTC is what is shown, marked "UTC".

const UTC_TIME = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?Z$/
const DAY = /^(\d{4})-(\d{2})-(\d{2})$/

// "2026-10-21T16:35:12.1234567Z" -> "21/10/2026 16:35:12 UTC". Anything else (the API always
// ends its times with Z) is returned unchanged, so a surprise stays visible.
export function formatUtc(value: string): string {
  const match = UTC_TIME.exec(value)
  if (!match) {
    return value
  }
  const [, year, month, day, hour, minute, second] = match
  return `${day}/${month}/${year} ${hour}:${minute}:${second} UTC`
}

// "2026-10-14" -> "14/10/2026".
export function formatDate(value: string): string {
  const match = DAY.exec(value)
  if (!match) {
    return value
  }
  const [, year, month, day] = match
  return `${day}/${month}/${year}`
}

// 500.5 -> "500,50 kg" (French number format, always 2 decimals like the database).
export function formatKg(quantity: number): string {
  const text = new Intl.NumberFormat('fr-FR', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(quantity)
  return `${text} kg`
}
