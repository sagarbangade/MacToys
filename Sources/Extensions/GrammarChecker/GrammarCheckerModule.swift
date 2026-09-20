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
        
        // Pre-warm the MLX model asynchronously
        Task {
            await LocalAIEngine.shared.loadModelIfNeeded()
        }
    }

    public func stop() {
        print("[GrammarChecker] stop() called")
        LocalAIEngine.shared.cancelLoading()
    }

    public func triggerAction() {
        if isEnabled {
            GrammarCheckerService.shared.execute()
        }
    }

    public func makeSettingsView() -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 12) {
                Text("Grammar Checker")
                    .font(.headline)
                Text("Select text in any app and press Cmd+Shift+G to instantly fix grammar.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("Powered by Llama-3.2 running locally on Apple Silicon.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                KeyboardShortcuts.Recorder("Shortcut:", name: .grammarChecker)
                Spacer()
            }
            .padding()
        )
    }
}

public extension KeyboardShortcuts.Name {
    static let grammarChecker = Self("grammarChecker", default: .init(.g, modifiers: [.command, .shift]))
}
