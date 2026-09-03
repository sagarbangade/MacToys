import Foundation
import SwiftUI

@Observable
@MainActor
public final class SettingsStore {
    public static let shared = SettingsStore()
    
    public var launchAtLogin: Bool {
        get { UserDefaults.standard.bool(forKey: "launchAtLogin") }
        set { UserDefaults.standard.set(newValue, forKey: "launchAtLogin") }
    }
    
    public var showMenuBarIcon: Bool {
        get { UserDefaults.standard.object(forKey: "showMenuBarIcon") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "showMenuBarIcon") }
    }
    
    public func isModuleEnabled(id: String) -> Bool {
        return UserDefaults.standard.object(forKey: "module_enabled_\(id)") as? Bool ?? false
    }
    
    public func setModuleEnabled(id: String, enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "module_enabled_\(id)")
    }
    
    private init() {}
}
