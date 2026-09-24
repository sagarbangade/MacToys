import Foundation
import SwiftUI

public enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case liquidGlass = "liquidGlass"     // macOS 27 Glassmorphism & Liquid Light
    case midnightDark = "midnightDark"   // OLED Obsidian & Siri Luminescence
    case crystalLight = "crystalLight"   // Ethereal Quartz Frost
    case system = "system"               // Native macOS Dynamic

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .liquidGlass: return "Liquid Glass"
        case .midnightDark: return "Midnight Dark"
        case .crystalLight: return "Crystal Light"
        case .system: return "System Auto"
        }
    }

    public var subtitle: String {
        switch self {
        case .liquidGlass: return "macOS 27 iridescent frost & specular light"
        case .midnightDark: return "Deep obsidian with neon luminescent aura"
        case .crystalLight: return "Clean airy quartz with subtle refractions"
        case .system: return "Adapts to system appearance automatically"
        }
    }

    public var icon: String {
        switch self {
        case .liquidGlass: return "sparkles"
        case .midnightDark: return "moon.stars.fill"
        case .crystalLight: return "sun.max.fill"
        case .system: return "circle.lefthalf.filled"
        }
    }
}

@Observable
@MainActor
public final class SettingsStore {
    public static let shared = SettingsStore()
    
    public var appearance: AppTheme {
        get {
            let raw = UserDefaults.standard.string(forKey: "appAppearance") ?? AppTheme.liquidGlass.rawValue
            return AppTheme(rawValue: raw) ?? .liquidGlass
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "appAppearance")
        }
    }
    
    public var launchAtLogin: Bool {
        get { UserDefaults.standard.bool(forKey: "launchAtLogin") }
        set { UserDefaults.standard.set(newValue, forKey: "launchAtLogin") }
    }
    
    public var showMenuBarIcon: Bool {
        get { UserDefaults.standard.object(forKey: "showMenuBarIcon") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "showMenuBarIcon") }
    }
    
    public func isModuleEnabled(id: String, defaultValue: Bool = false) -> Bool {
        UserDefaults.standard.object(forKey: "module_enabled_\(id)") as? Bool ?? defaultValue
    }
    
    public func setModuleEnabled(id: String, enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "module_enabled_\(id)")
    }
    
    private init() {}
}
