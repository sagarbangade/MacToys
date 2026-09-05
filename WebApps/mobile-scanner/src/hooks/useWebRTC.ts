import { useEffect, useRef, useState, useCallback } from 'react'
import Peer, { DataConnection } from 'peerjs'

interface UseWebRTCReturn {
  status: string
  connected: boolean
  send: (text: string) => void
}

export function useWebRTC(roomId: string | null): UseWebRTCReturn {
  const [status, setStatus] = useState('Initializing...')
  const [connected, setConnected] = useState(false)
  const connRef = useRef<DataConnection | null>(null)

  useEffect(() => {
    if (!roomId) {
      setStatus('Error: No room ID in URL')
      return
    }

    const peer = new Peer()

    peer.on('open', () => {
      setStatus('Connecting to Mac...')
      const conn = peer.connect(roomId, { reliable: true })

      conn.on('open', () => {
        connRef.current = conn
        setConnected(true)
        setStatus('Connected to Mac!')
      })

      conn.on('close', () => {
        connRef.current = null
        setConnected(false)
        setStatus('Disconnected from Mac')
      })

      conn.on('error', (err) => {
        setStatus('Connection error: ' + String(err))
      })
    })

    peer.on('error', (err) => {
      setStatus('Network error: ' + err.type)
    })

    return () => {
      peer.destroy()
    }
  }, [roomId])

  const send = useCallback((text: string) => {
    connRef.current?.send({ type: 'scan', payload: text })
  }, [])

  return { status, connected, send }
}
