import { useState, useEffect, useRef, useCallback } from 'react'
import Peer, { DataConnection } from 'peerjs'
import QRCode from 'qrcode'

export function useWebRTC(roomID: string | null) {
  const [connected, setConnected] = useState(false)
  const peerRef = useRef<Peer | null>(null)
  const connRef = useRef<DataConnection | null>(null)

  useEffect(() => {
    if (!roomID) return

    const peer = new Peer()
    peerRef.current = peer

    peer.on('open', () => {
      console.log('Connecting to room:', roomID)
      // Reliable true is important for larger payloads like images
      const conn = peer.connect(roomID, { reliable: true })
      connRef.current = conn

      conn.on('open', () => {
        console.log('Connected to Mac!')
        setConnected(true)
      })

      conn.on('close', () => {
        console.log('Connection closed')
        setConnected(false)
      })

      conn.on('error', (err) => {
        console.error('Connection error:', err)
        setConnected(false)
      })
    })

    peer.on('error', (err) => {
      console.error('Peer error:', err)
    })

    return () => {
      connRef.current?.close()
      peerRef.current?.destroy()
    }
  }, [roomID])

  const sendPayload = useCallback((payload: string) => {
    if (connRef.current && connected) {
      connRef.current.send({ type: 'scan', payload })
    }
  }, [connected])

  const sendImageOCR = useCallback((jpegBase64: string) => {
    if (connRef.current && connected) {
      connRef.current.send({ type: 'image_ocr', payload: jpegBase64 })
    }
  }, [connected])

  const generateQRUrl = useCallback(() => {
    if (!roomID) return ''
    const url = window.location.href
    let qrDataUrl = ''
    // Synchronous generation for simple use case
    QRCode.toDataURL(url, { width: 250, margin: 1 }, (err, url) => {
      if (!err) qrDataUrl = url
    })
    return qrDataUrl
  }, [roomID])

  return { connected, sendPayload, sendImageOCR, generateQRUrl }
}
