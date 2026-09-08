import Foundation
import Cocoa
import SwiftUI
import MacToysKit
@preconcurrency import KeyboardShortcuts

@MainActor
public final class TypingAssistModule: UtilityModule {
    public static let shared = TypingAssistModule()

    public let id = "typingAssist"
    public let displayName = "Typing Assistant"
    public let description = "System-wide inline predictive text with learning"
    public let iconSymbol = "text.badge.plus"

    public var isEnabled: Bool = false
    public let isEnabledByDefault = true
    public var requiredPermissions: [PermissionRequirement] {
        [.accessibility]
    }
    public var shortcutName: KeyboardShortcuts.Name? { nil }

    private init() {}

    public func start() {
        // No guard on isEnabled — ModuleRegistry sets it before calling us
        print("[TypingAssist] start() called")
        InputMonitor.shared.start()
    }

    public func stop() {
        print("[TypingAssist] stop() called")
        InputMonitor.shared.stop()
    }

    public func triggerAction() {
        // Always-on module, no manual trigger
    }

    public func makeSettingsView() -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 12) {
                Text("Typing Assistant")
                    .font(.headline)
                Text("Predicts next words as you type across all apps. Press Tab to accept a suggestion.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("Learns from your typing patterns over time.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding()
        )
    }
}
