import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// Relative base so the built app works both online at any sub-path
// (e.g. GitHub Pages /crackeroftools/) and when installed as a PWA.
// https://vite.dev/config/
export default defineConfig({
  base: './',
  plugins: [react()],
})
