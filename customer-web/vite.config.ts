import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      '/health': 'http://localhost:8080',
      '/auth': 'http://localhost:8080',
      '/vehicles': 'http://localhost:8080',
      '/rides': 'http://localhost:8080',
      '/bookings': 'http://localhost:8080',
      '/notifications': 'http://localhost:8080',
      '/ratings': 'http://localhost:8080',
      '/recurring-schedules': 'http://localhost:8080',
      '/locations': 'http://localhost:8080',
      '/upload': 'http://localhost:8080',
      '/chat': 'http://localhost:8080',
      '/wallet': 'http://localhost:8080',
      '/payments': 'http://localhost:8080',
      '/referrals': 'http://localhost:8080',
    },
  },
})
