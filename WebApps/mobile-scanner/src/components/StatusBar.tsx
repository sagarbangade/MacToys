interface StatusBarProps {
  message: string
  connected: boolean
}

export function StatusBar({ message, connected }: StatusBarProps) {
  return (
    <div
      style={{
        padding: 12,
        textAlign: 'center',
        backgroundColor: connected ? '#27ae60' : '#c0392b',
        fontSize: 14,
        fontWeight: 'bold',
        color: '#fff',
        transition: 'background-color 0.3s',
      }}
    >
      {message}
    </div>
  )
}
