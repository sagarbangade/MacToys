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
        AnyView(TypingAssistSettingsView())
    }
}

struct TypingAssistSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("ASSISTANCE ENGINE")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                
                PremiumCard {
                    PremiumRow(
                        icon: "keyboard.fill",
                        iconColor: .teal,
                        title: "Inline Word Prediction",
                        subtitle: "Predicts next words in real time as you type across all apps"
                    ) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 16))
                    }
                    
                    PremiumDivider()
                    
                    PremiumRow(
                        icon: "arrow.right.to.line.compact",
                        iconColor: .blue,
                        title: "Tab Acceptance",
                        subtitle: "Press the Tab key at any time to accept the suggested prediction"
                    ) {
                        Text("Tab ⇥")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.blue.opacity(0.15)))
                    }
                }
            }
        }
    }
}
