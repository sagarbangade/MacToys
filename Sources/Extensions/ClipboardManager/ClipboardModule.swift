import Foundation
import Cocoa
import SwiftUI
import MacToysKit
@preconcurrency import KeyboardShortcuts

@MainActor
public class TargetAppTracker: ObservableObject {
    public static let shared = TargetAppTracker()
    @Published public var targetAppName: String = "Active App"
    public var targetApp: NSRunningApplication?
    
    public func updateTargetApp() {
        if let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier != Bundle.main.bundleIdentifier {
            self.targetAppName = app.localizedName ?? "Active App"
            self.targetApp = app
        }
    }
}

@MainActor
public final class ClipboardModule: UtilityModule {
    public let id = "clipboardManager"
    public let displayName = "Clipboard History"
    public let description = "Raycast-style clipboard manager with auto-paste"
    public let iconSymbol = "doc.on.clipboard"
    
    public var isEnabled: Bool = false
    public let requiredPermissions: [PermissionRequirement] = [.accessibility]
    public var shortcutName: KeyboardShortcuts.Name? { .clipboardManager }
    
    private var window: ClipboardOverlayWindow?
    private let watcher = ClipboardWatcher()
    private var globalEscapeMonitor: Any?
    
    public init() {}
    
    public func triggerAction() {
        if isEnabled {
            toggleWindow()
        }
    }
    
    public func start() {
        watcher.start()
        KeyboardShortcuts.onKeyDown(for: .clipboardManager) { [weak self] in
            self?.toggleWindow()
        }
    }
    
    public func stop() {
        watcher.stop()
        KeyboardShortcuts.disable(.clipboardManager)
        hideWindow()
    }
    
    public func makeSettingsView() -> AnyView {
        AnyView(ClipboardSettingsView())
    }
    
    private func toggleWindow() {
        if window?.isVisible == true {
            hideWindow()
        } else {
            showWindow()
        }
    }
    
    private func showWindow() {
        TargetAppTracker.shared.updateTargetApp()
        
        if window == nil {
            window = ClipboardOverlayWindow()
            
            // Add a global monitor to close on escape when focus is lost
            globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 {
                    self?.hideWindow()
                }
            }
        }
        
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    
    private func hideWindow() {
        window?.orderOut(nil)
    }
}

public extension KeyboardShortcuts.Name {
    static let clipboardManager = Self("clipboardManager", default: .init(.v, modifiers: [.command, .shift]))
}

struct ClipboardSettingsView: View {
    @ObservedObject var store = ClipboardStore.shared
    
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Shortcut:", name: .clipboardManager)
            
            HStack {
                Text("Stored Items:")
                Text("\(store.items.count)")
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Clear History") {
                    store.items.removeAll()
                }
            }
            .padding(.top, 10)
        }
        .padding()
    }
}
