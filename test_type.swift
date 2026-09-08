import Foundation
import CoreGraphics

func typeText(_ text: String) {
    let source = CGEventSource(stateID: .hidSystemState)
    let utf16Chars = Array(text.utf16)
    
    for char in utf16Chars {
        var unit = char
        if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
           let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
            down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)
            up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)
            
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }
}
print("Compiles fine!")
