import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.tsx'

// Disable auto-rotation on supported devices
if (typeof window !== 'undefined' && 'screen' in window && 'orientation' in window.screen) {
  try {
    const screenOrientation = window.screen.orientation as any;
    if (typeof screenOrientation.lock === 'function') {
      screenOrientation.lock('portrait').catch(() => {});
    }
  } catch {
    // Ignore environments where screen orientation lock is disallowed
  }
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
