import { useState, useCallback, useEffect } from 'react'
import { StatusBar } from './components/StatusBar'
import { Scanner } from './components/Scanner'
import { SuccessOverlay } from './components/SuccessOverlay'
import { useWebRTC } from './hooks/useWebRTC'

const styles: Record<string, React.CSSProperties> = {
  app: {
    height: '100%',
    display: 'flex',
    flexDirection: 'column',
    fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif',
  },
  scannerArea: {
    flex: 1,
    position: 'relative',
    display: 'flex',
    backgroundColor: '#000',
  },
  qrContainer: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    display: 'flex',
    justifyContent: 'center',
    alignItems: 'center',
    zIndex: 10,
    pointerEvents: 'none',
  },
  qrImage: {
    width: 250,
    height: 250,
    border: '4px solid #fff',
    borderRadius: 16,
    boxShadow: '0 8px 30px rgba(0,0,0,0.5)',
    backgroundColor: '#fff',
    padding: 8,
  }
}

export function App() {
  const [roomID, setRoomID] = useState<string | null>(null)
  const { connected, sendPayload, sendImageOCR, generateQRUrl } = useWebRTC(roomID)
  const [showSuccess, setShowSuccess] = useState(false)

  // Get room ID from URL search params
  useEffect(() => {
    const params = new URLSearchParams(window.location.search)
    const room = params.get('room')
    if (room) {
      setRoomID(room)
    } else {
      // For local testing without Mac
      console.warn("No room ID in URL")
    }
  }, [])

  const handleQRScan = useCallback((text: string) => {
    if (!connected) return
    console.log("Scanned QR:", text)
    sendPayload(text)
    setShowSuccess(true)
    setTimeout(() => setShowSuccess(false), 2000)
  }, [connected, sendPayload])

  const handleTextScan = useCallback((jpegBase64: string) => {
    if (!connected) return
    console.log("Scanned Text Image")
    sendImageOCR(jpegBase64)
    setShowSuccess(true)
    setTimeout(() => setShowSuccess(false), 2000)
  }, [connected, sendImageOCR])

  const qrUrl = roomID ? generateQRUrl() : null

  return (
    <div style={styles.app}>
      <StatusBar 
        connected={connected} 
        message={connected ? "Connected to Mac" : "Waiting for Mac..."} 
      />
      
      <div style={styles.scannerArea}>
        {/* Only show scanner if connected, or if testing locally (no roomID) */}
        {(connected || !roomID) ? (
          <Scanner 
            onQRScan={handleQRScan} 
            onTextScan={handleTextScan}
            enabled={connected || !roomID} 
          />
        ) : (
          <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', color: '#fff' }}>
            <p style={{ marginBottom: 20 }}>Scan this code from another device to connect:</p>
            {qrUrl && <img src={qrUrl} style={styles.qrImage} alt="Connection QR" />}
          </div>
        )}
        
        <SuccessOverlay visible={showSuccess} />
      </div>
    </div>
  )
}
