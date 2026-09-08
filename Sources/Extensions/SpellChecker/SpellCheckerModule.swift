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
    public let iconSymbol = "textformat.abc.dottedunderline"

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
        AnyView(
            VStack(alignment: .leading, spacing: 12) {
                Text("Spell Checker")
                    .font(.headline)
                Text("Highlights misspelled words with red underlines across all apps. Hover over a word to see the correction.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("Works in native macOS apps (TextEdit, Notes, Mail, Safari).")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding()
        )
    }
}
