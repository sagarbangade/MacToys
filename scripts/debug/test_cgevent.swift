import AppKit
import ApplicationServices

let source = CGEventSource(stateID: .hidSystemState)
let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
keyDown?.flags = .maskCommand
let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
keyUp?.flags = .maskCommand

print("Testing CGEvent post...")
keyDown?.post(tap: .cghidEventTap)
keyUp?.post(tap: .cghidEventTap)
print("Posted without crash.")
