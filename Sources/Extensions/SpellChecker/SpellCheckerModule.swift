import Foundation
import SwiftUI
import MacToysKit
@preconcurrency import KeyboardShortcuts

@MainActor
public final class SpellCheckerModule: UtilityModule {
    public static let shared = SpellCheckerModule()

    public let id = "spellChecker"
    public let displayName = "Spell Checker"
    public let description = "Highlights misspelled words with red underlines and suggests corrections on hover"
    public let iconSymbol = "textformat.abc"

    public var isEnabled: Bool = false
    public let isEnabledByDefault = false
    public var requiredPermissions: [PermissionRequirement] {
        [.accessibility]
    }
    public var shortcutName: KeyboardShortcuts.Name? { nil }

    private init() {}

    public func start() {
        print("[SpellChecker] start() called")
        SpellCheckMonitor.shared.start()
    }

    public func stop() {
        print("[SpellChecker] stop() called")
        SpellCheckMonitor.shared.stop()
    }

    public func triggerAction() {
        // Always-on module, no manual trigger
    }

    public func makeSettingsView() -> AnyView {
        AnyView(SpellCheckerSettingsView())
    }
}

struct SpellCheckerSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("SPELL CHECKING ENGINE")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                
                PremiumCard {
                    PremiumRow(
                        icon: "textformat.abc",
                        iconColor: .red,
                        title: "Real-Time Detection",
                        subtitle: "Underlines misspellings in red across apps via macOS Accessibility"
                    ) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 16))
                    }
                    
                    PremiumDivider()
                    
                    PremiumRow(
                        icon: "hand.tap.fill",
                        iconColor: .orange,
                        title: "Interactive Correction",
                        subtitle: "Hover over underlined words to view smart correction popover"
                    ) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 16))
                    }
                    
                    PremiumDivider()
                    
                    PremiumRow(
                        icon: "lock.shield.fill",
                        iconColor: .teal,
                        title: "On-Device Dictionary",
                        subtitle: "Zero network telemetry; spellchecking runs 100% on your Mac"
                    ) {
                        Text("Private")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.teal)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.teal.opacity(0.15)))
                    }
                }
            }
        }
    }
}
