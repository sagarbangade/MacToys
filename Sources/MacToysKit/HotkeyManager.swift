import Foundation
import KeyboardShortcuts

@MainActor
public final class HotkeyManager {
    public static let shared = HotkeyManager()
    
    private init() {}
    
    public func register(name: KeyboardShortcuts.Name, action: @escaping @MainActor () -> Void) {
        KeyboardShortcuts.onKeyDown(for: name, action: action)
    }
}
