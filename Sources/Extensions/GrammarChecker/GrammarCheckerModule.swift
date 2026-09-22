import Foundation
import Cocoa
import SwiftUI
import MacToysKit
@preconcurrency import KeyboardShortcuts

@MainActor
public final class GrammarCheckerModule: UtilityModule {
    public static let shared = GrammarCheckerModule()

    public let id = "grammarChecker"
    public let displayName = "Grammar Checker"
    public let description = "Locally corrects grammar and tone via MLX LLM"
    public let iconSymbol = "text.badge.checkmark"

    public var isEnabled: Bool = false
    public let isEnabledByDefault = true
    public var requiredPermissions: [PermissionRequirement] {
        [.accessibility]
    }
    public var shortcutName: KeyboardShortcuts.Name? { .grammarChecker }

    private init() {}

    public func start() {
        print("[GrammarChecker] start() called")
        // Register hotkey
        KeyboardShortcuts.onKeyDown(for: .grammarChecker) { [weak self] in
            self?.triggerAction()
        }
        
        // Start the native overlay engine
        GrammarOverlayManager.shared.start()
        
        // Boot up the Python sidecar immediately if enabled
        Task {
            do {
                try await GECSidecar.shared.start()
            } catch {
                print("[GrammarChecker] Failed to start sidecar: \(error)")
            }
        }
    }

    public func stop() {
        print("[GrammarChecker] stop() called")
        GrammarOverlayManager.shared.stop()
        Task {
            await GECSidecar.shared.stop()
        }
    }

    public func triggerAction() {
        if isEnabled {
            GrammarCheckerService.shared.execute()
        }
    }

    public func makeSettingsView() -> AnyView {
        AnyView(GrammarCheckerSettingsView())
    }
}

public extension KeyboardShortcuts.Name {
    static let grammarChecker = Self("grammarChecker", default: .init(.g, modifiers: [.command, .shift]))
}
