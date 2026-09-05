import { useEffect, useRef, useState, useCallback } from 'react'

interface UseCameraReturn {
  videoRef: React.RefObject<HTMLVideoElement | null>
  started: boolean
  error: string | null
  start: () => void
  captureFrame: () => ImageData | null
}

/**
 * Raw MediaDevices camera hook.
 *
 * Forces the main back camera by requesting the highest resolution available
 * with facingMode "environment". On multi-lens Android phones, the OS maps
 * the highest-res "environment" stream to the primary 1x sensor (not the
 * ultrawide or macro).
 */
export function useCamera(): UseCameraReturn {
  const videoRef = useRef<HTMLVideoElement | null>(null)
  const canvasRef = useRef<HTMLCanvasElement | null>(null)
  const streamRef = useRef<MediaStream | null>(null)
  const [started, setStarted] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // Create an offscreen canvas for frame capture
  useEffect(() => {
    canvasRef.current = document.createElement('canvas')
  }, [])

  const start = useCallback(async () => {
    try {
      // These constraints force the OS to select the main (highest-res) back camera
      const stream = await navigator.mediaDevices.getUserMedia({
        video: {
          facingMode: { exact: 'environment' },
          width: { ideal: 3840 },    // Request 4K — OS picks the sensor capable of it
          height: { ideal: 2160 },
        },
        audio: false,
      })

      streamRef.current = stream

      if (videoRef.current) {
        videoRef.current.srcObject = stream
        await videoRef.current.play()
        setStarted(true)
        setError(null)
      }
    } catch (err) {
      // Fallback: if exact environment fails, try without exact
      try {
        const stream = await navigator.mediaDevices.getUserMedia({
          video: {
            facingMode: 'environment',
            width: { ideal: 1920 },
            height: { ideal: 1080 },
          },
          audio: false,
        })

        streamRef.current = stream

        if (videoRef.current) {
          videoRef.current.srcObject = stream
          await videoRef.current.play()
          setStarted(true)
          setError(null)
        }
      } catch (fallbackErr) {
        setError('Camera access denied or unavailable: ' + String(fallbackErr))
      }
    }
  }, [])

  const captureFrame = useCallback((): ImageData | null => {
    const video = videoRef.current
    const canvas = canvasRef.current
    if (!video || !canvas || video.readyState < 2) return null

    canvas.width = video.videoWidth
    canvas.height = video.videoHeight
    const ctx = canvas.getContext('2d', { willReadFrequently: true })
    if (!ctx) return null

    ctx.drawImage(video, 0, 0)
    return ctx.getImageData(0, 0, canvas.width, canvas.height)
  }, [])

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      streamRef.current?.getTracks().forEach(t => t.stop())
    }
  }, [])

  return { videoRef, started, error, start, captureFrame }
}
