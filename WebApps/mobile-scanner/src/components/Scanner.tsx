import { useEffect, useRef, useCallback } from 'react'
import { useCamera } from '../hooks/useCamera'
import jsQR from 'jsqr'

interface ScannerProps {
  onScan: (text: string) => void
  enabled: boolean
}

const styles: Record<string, React.CSSProperties> = {
  container: {
    flex: 1, width: '100%', position: 'relative',
    display: 'flex', justifyContent: 'center', alignItems: 'center',
    backgroundColor: '#000', overflow: 'hidden',
  },
  video: {
    width: '100%', height: '100%', objectFit: 'cover',
  },
  startBtn: {
    backgroundColor: '#3498db', color: '#fff', border: 'none',
    borderRadius: 50, padding: '16px 32px', fontSize: 18,
    fontWeight: 'bold', boxShadow: '0 4px 15px rgba(0,0,0,0.3)',
    cursor: 'pointer',
  },
  overlay: {
    position: 'absolute', top: '50%', left: '50%',
    transform: 'translate(-50%, -50%)',
    width: 250, height: 250,
    border: '2px solid rgba(52,152,219,0.8)',
    borderRadius: 12,
    boxShadow: '0 0 0 9999px rgba(0,0,0,0.4)',
    pointerEvents: 'none',
  },
  error: {
    color: '#e74c3c', padding: 20, textAlign: 'center',
  },
}

export function Scanner({ onScan, enabled }: ScannerProps) {
  const { videoRef, started, error, start, captureFrame } = useCamera()
  const scanningRef = useRef(false)
  const lastScannedRef = useRef('')
  const lastScannedTimeRef = useRef(0)

  // Scan loop: capture frames and decode QR codes using jsQR
  const scanLoop = useCallback(() => {
    if (!scanningRef.current) return

    const imageData = captureFrame()
    if (imageData) {
      const code = jsQR(imageData.data, imageData.width, imageData.height, {
        inversionAttempts: 'dontInvert',
      })

      if (code?.data) {
        const now = Date.now()
        // Debounce: don't re-fire the same code within 3 seconds
        if (code.data !== lastScannedRef.current || now - lastScannedTimeRef.current > 3000) {
          lastScannedRef.current = code.data
          lastScannedTimeRef.current = now
          onScan(code.data)
        }
      }
    }

    requestAnimationFrame(scanLoop)
  }, [captureFrame, onScan])

  // Start scanning loop when camera is ready and connection is up
  useEffect(() => {
    if (started && enabled) {
      scanningRef.current = true
      requestAnimationFrame(scanLoop)
    }
    return () => {
      scanningRef.current = false
    }
  }, [started, enabled, scanLoop])

  if (error) {
    return (
      <div style={styles.container}>
        <div style={styles.error}>
          <p>{error}</p>
          <button style={styles.startBtn} onClick={start}>Retry Camera</button>
        </div>
      </div>
    )
  }

  if (!started) {
    return (
      <div style={styles.container}>
        <button style={styles.startBtn} onClick={start}>
          Tap to Start Camera
        </button>
      </div>
    )
  }

  return (
    <div style={styles.container}>
      <video ref={videoRef} style={styles.video} playsInline muted />
      <div style={styles.overlay} />
    </div>
  )
}
