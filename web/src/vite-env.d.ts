// Types of the variables we read from import.meta.env (see src/config.ts).
interface ImportMetaEnv {
  readonly VITE_API_URL?: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
