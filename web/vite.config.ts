/// <reference types="vitest/config" />
import tailwindcss from '@tailwindcss/vite'
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react(), tailwindcss()],
  // The CORS policy of the API names this exact origin (http://localhost:5173).
  // If the port is taken, stop instead of silently moving to another port.
  server: { port: 5173, strictPort: true },
  test: {
    // Puts back the real fetch (and any other global) replaced by vi.stubGlobal after each test.
    unstubGlobals: true,
  },
})
