import { useState } from 'react'
import { useWebRTC } from './hooks/useWebRTC'
import { Scanner } from './components/Scanner'
import { StatusBar } from './components/StatusBar'
import { SuccessOverlay } from './components/SuccessOverlay'

const styles: Record<string, React.CSSProperties> = {
  app: {
    margin: 0, padding: 0, backgroundColor: '#000', color: '#fff',
    fontFamily: '-apple-system, system-ui, sans-serif',
    display: 'flex', flexDirection: 'column', height: '100vh', overflow: 'hidden',
  },
  header: {
    padding: 16, textAlign: 'center', backgroundColor: '#1a1a1a',
    fontWeight: 'bold', fontSize: 18, borderBottom: '1px solid #333',
  },
}

function App() {
  const params = new URLSearchParams(window.location.search)
  const roomId = params.get('room')

  const { status, connected, send } = useWebRTC(roomId)
  const [showSuccess, setShowSuccess] = useState(false)

  const handleScan = (text: string) => {
    if (!connected) return
    send(text)
    setShowSuccess(true)
    if (navigator.vibrate) navigator.vibrate(200)
    setTimeout(() => setShowSuccess(false), 2000)
  }

  return (
    <div style={styles.app}>
      <div style={styles.header}>MacToys Scanner</div>
      <Scanner onScan={handleScan} enabled={connected} />
      <StatusBar message={status} connected={connected} />
      <SuccessOverlay visible={showSuccess} />
    </div>
  )
}

export default App
