import { useEffect, useRef, useCallback, useState } from 'react'
import { useCamera } from '../hooks/useCamera'
import jsQR from 'jsqr'

interface ScannerProps {
  onQRScan: (text: string) => void
  onTextScan: (jpegBase64: string) => void
  enabled: boolean
}

const styles: Record<string, React.CSSProperties> = {
  container: {
    flex: 1, width: '100%', position: 'relative',
    display: 'flex', flexDirection: 'column',
    backgroundColor: '#000', overflow: 'hidden',
  },
  videoContainer: {
    flex: 1, position: 'relative', display: 'flex',
    justifyContent: 'center', alignItems: 'center', overflow: 'hidden'
  },
  video: {
    width: '100%', height: '100%', objectFit: 'cover',
  },
  startBtn: {
    backgroundColor: '#3498db', color: '#fff', border: 'none',
    borderRadius: 50, padding: '16px 32px', fontSize: 18,
    fontWeight: 'bold', boxShadow: '0 4px 15px rgba(0,0,0,0.3)',
    cursor: 'pointer', zIndex: 10,
  },
  overlayQR: {
    position: 'absolute', top: '50%', left: '50%',
    transform: 'translate(-50%, -50%)',
    width: 250, height: 250,
    border: '3px solid #2ecc71',
    borderRadius: 12,
    boxShadow: '0 0 0 9999px rgba(0,0,0,0.5)',
    pointerEvents: 'none',
  },
  overlayText: {
    position: 'absolute', top: '20%', bottom: '20%', left: '10%', right: '10%',
    border: '2px dashed #f1c40f',
    borderRadius: 12,
    boxShadow: '0 0 0 9999px rgba(0,0,0,0.5)',
    pointerEvents: 'none',
  },
  controls: {
    height: 100, backgroundColor: '#111',
    display: 'flex', justifyContent: 'space-around', alignItems: 'center',
    paddingBottom: 'env(safe-area-inset-bottom, 20px)'
  },
  tabBtn: {
    background: 'none', border: 'none', color: '#fff',
    fontSize: 16, fontWeight: 'bold', padding: '12px 24px',
    opacity: 0.5, transition: 'opacity 0.2s',
  },
  tabBtnActive: {
    opacity: 1, color: '#3498db', borderBottom: '2px solid #3498db'
  },
  shutterBtn: {
    position: 'absolute', bottom: 120, left: '50%', transform: 'translateX(-50%)',
    width: 70, height: 70, borderRadius: 35,
    backgroundColor: 'rgba(255,255,255,0.3)',
    border: '4px solid #fff',
    display: 'flex', justifyContent: 'center', alignItems: 'center',
    cursor: 'pointer', zIndex: 10
  },
  shutterInner: {
    width: 54, height: 54, borderRadius: 27, backgroundColor: '#fff'
  },
  error: {
    color: '#e74c3c', padding: 20, textAlign: 'center',
  },
}

export function Scanner({ onQRScan, onTextScan, enabled }: ScannerProps) {
  const { videoRef, started, error, start, captureFrame, getJpegBase64 } = useCamera()
  const [mode, setMode] = useState<'qr' | 'text'>('qr')
  const scanningRef = useRef(false)
  const lastScannedRef = useRef('')
  const lastScannedTimeRef = useRef(0)
  
  // Try to use native barcode detector if available
  const barcodeDetectorRef = useRef<any>(null)
  
  useEffect(() => {
    if ('BarcodeDetector' in window) {
      try {
        // @ts-ignore
        barcodeDetectorRef.current = new window.BarcodeDetector({ formats: ['qr_code'] })
      } catch (e) {
        console.error("BarcodeDetector not supported", e)
      }
    }
  }, [])

  // Scan loop for QR Mode
  const scanLoop = useCallback(async () => {
    if (!scanningRef.current || mode !== 'qr') return

    const now = Date.now()
    if (now - lastScannedTimeRef.current > 1500) { // check every 1.5s if recently scanned, otherwise fast
      
      const video = videoRef.current
      if (video && video.readyState === video.HAVE_ENOUGH_DATA) {
        
        let foundCode = null
        
        if (barcodeDetectorRef.current) {
          try {
            const barcodes = await barcodeDetectorRef.current.detect(video)
            if (barcodes.length > 0) {
              foundCode = barcodes[0].rawValue
            }
          } catch (e) {
             // fallback to jsQR
          }
        }
        
        if (!foundCode) {
          const imageData = captureFrame()
          if (imageData) {
            const code = jsQR(imageData.data, imageData.width, imageData.height, {
              inversionAttempts: 'dontInvert',
            })
            if (code?.data) foundCode = code.data
          }
        }

        if (foundCode) {
          if (foundCode !== lastScannedRef.current || now - lastScannedTimeRef.current > 3000) {
            lastScannedRef.current = foundCode
            lastScannedTimeRef.current = now
            onQRScan(foundCode)
          }
        }
      }
    }

    if (scanningRef.current && mode === 'qr') {
      requestAnimationFrame(scanLoop)
    }
  }, [captureFrame, mode, onQRScan, videoRef])

  useEffect(() => {
    if (started && enabled && mode === 'qr') {
      scanningRef.current = true
      requestAnimationFrame(scanLoop)
    }
    return () => {
      scanningRef.current = false
    }
  }, [started, enabled, mode, scanLoop])

  const handleShutter = () => {
    if (mode === 'text') {
      const base64 = getJpegBase64(0.8) // 80% quality JPEG
      if (base64) {
        onTextScan(base64)
      }
    }
  }

  if (error) {
    return (
      <div style={styles.container}>
        <div style={styles.videoContainer}>
          <div style={styles.error}>
            <p>{error}</p>
            <button style={styles.startBtn} onClick={start}>Retry Camera</button>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div style={styles.container}>
      <div style={styles.videoContainer}>
        {!started ? (
          <button style={styles.startBtn} onClick={start}>
            Tap to Start Camera
          </button>
        ) : (
          <>
            <video ref={videoRef} style={styles.video} playsInline muted />
            <div style={mode === 'qr' ? styles.overlayQR : styles.overlayText} />
            
            {mode === 'text' && (
              <div style={styles.shutterBtn} onClick={handleShutter}>
                <div style={styles.shutterInner} />
              </div>
            )}
          </>
        )}
      </div>
      
      <div style={styles.controls}>
        <button 
          style={{...styles.tabBtn, ...(mode === 'qr' ? styles.tabBtnActive : {})}}
          onClick={() => setMode('qr')}
        >
          QR CODE
        </button>
        <button 
          style={{...styles.tabBtn, ...(mode === 'text' ? styles.tabBtnActive : {})}}
          onClick={() => setMode('text')}
        >
          TEXT OCR
        </button>
      </div>
    </div>
  )
}
