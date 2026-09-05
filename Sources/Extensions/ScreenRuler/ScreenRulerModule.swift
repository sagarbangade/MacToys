import Foundation
import Cocoa
import SwiftUI
import MacToysKit
@preconcurrency import KeyboardShortcuts

@MainActor
public final class ScreenRulerModule: UtilityModule {
    public let id = "screenRuler"
    public let displayName = "Screen Ruler"
    public let description = "Measure pixel dimensions on your screen"
    public let iconSymbol = "ruler"
    
    public var isEnabled: Bool = false
    public let requiredPermissions: [PermissionRequirement] = []
    public var shortcutName: KeyboardShortcuts.Name? { .screenRuler }
    
    private var windows: [NSWindow] = []
    private var localEscapeMonitor: Any?
    private var globalEscapeMonitor: Any?
    
    public init() {}
    
    public func triggerAction() {
        if isEnabled {
            toggleRuler()
        }
    }
    
    public func start() {
        KeyboardShortcuts.onKeyDown(for: .screenRuler) { [weak self] in
            self?.toggleRuler()
        }
    }
    
    public func stop() {
        KeyboardShortcuts.disable(.screenRuler)
        hideRuler()
    }
    
    public func makeSettingsView() -> AnyView {
        AnyView(ScreenRulerSettingsView())
    }
    
    private func toggleRuler() {
        if windows.isEmpty {
            showRuler()
        } else {
            hideRuler()
        }
    }
    
    private func showRuler() {
        hideRuler()
        
        for screen in NSScreen.screens {
            let window = RulerOverlayWindow(contentRect: screen.frame)
            let view = RulerView(frame: window.contentView!.bounds)
            
            view.onCancel = { [weak self] in
                self?.hideRuler()
            }
            
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        
        NSApp.activate(ignoringOtherApps: true)
        
        // Add a local monitor to catch Escape if the app is active
        localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape key
                self?.hideRuler()
                return nil
            }
            return event
        }
        
        globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape key
                self?.hideRuler()
            }
        }
    }
    
    private func hideRuler() {
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        
        if let monitor = localEscapeMonitor {
            NSEvent.removeMonitor(monitor)
            localEscapeMonitor = nil
        }
        if let monitor = globalEscapeMonitor {
            NSEvent.removeMonitor(monitor)
            globalEscapeMonitor = nil
        }
    }
}

public extension KeyboardShortcuts.Name {
    static let screenRuler = Self("screenRuler", default: .init(.m, modifiers: [.command, .shift]))
}

struct ScreenRulerSettingsView: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Shortcut:", name: .screenRuler)
            Text("Press the hotkey to activate the screen ruler. Click and drag anywhere to measure pixels. Press Esc to exit, or right-click to clear measurement.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}
