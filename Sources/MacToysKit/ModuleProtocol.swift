import Foundation
import SwiftUI
import KeyboardShortcuts

public enum PermissionRequirement {
    case accessibility
    case screenRecording
    case fullDiskAccess
}

@MainActor
public protocol UtilityModule: ObservableObject, Identifiable {
    var id: String { get }
    var displayName: String { get }
    var description: String { get }
    var iconSymbol: String { get }
    
    var isEnabled: Bool { get set }
    /// Used only until the user has explicitly chosen a state in Preferences.
    var isEnabledByDefault: Bool { get }
    var requiredPermissions: [PermissionRequirement] { get }
    var shortcutName: KeyboardShortcuts.Name? { get }
    
    func start()
    func stop()
    func makeSettingsView() -> AnyView
    func triggerAction()
}

public extension UtilityModule {
    var isEnabledByDefault: Bool { false }
}
