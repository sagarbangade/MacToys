interface SuccessOverlayProps {
  visible: boolean
}

export function SuccessOverlay({ visible }: SuccessOverlayProps) {
  return (
    <div
      style={{
        position: 'absolute',
        top: 0, left: 0, right: 0, bottom: 0,
        backgroundColor: 'rgba(39, 174, 96, 0.95)',
        display: 'flex',
        flexDirection: 'column',
        justifyContent: 'center',
        alignItems: 'center',
        zIndex: 9999,
        opacity: visible ? 1 : 0,
        pointerEvents: visible ? 'all' : 'none',
        transition: 'opacity 0.2s',
        color: '#fff',
      }}
    >
      <div style={{ fontSize: 80, marginBottom: 16 }}>✓</div>
      <h2>Sent to Mac!</h2>
    </div>
  )
}
