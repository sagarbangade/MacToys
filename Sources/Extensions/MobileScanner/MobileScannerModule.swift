import Foundation
import Cocoa
import SwiftUI
import MacToysKit
@preconcurrency import KeyboardShortcuts

@MainActor
public final class MobileScannerModule: UtilityModule, WebRTCEngineDelegate {
    public let id = "mobileScanner"
    public let displayName = "Mobile Scanner"
    public let description = "Scan real-world text with your phone and beam it to Mac"
    public let iconSymbol = "iphone.and.arrow.forward"
    
    public var isEnabled: Bool = false
    public let requiredPermissions: [PermissionRequirement] = [] // WebRTC handles this
    public var shortcutName: KeyboardShortcuts.Name? { .mobileScanner }
    
    private var overlayWindow: MobileScannerOverlayWindow?
    private var engine: WebRTCEngine?
    
    // The user will need to host the index.html on their GitHub Pages and put the URL here.
    @AppStorage("mobileScannerGithubURL") private var githubPagesURL: String = "https://sagarbangade.github.io/mactoys-mobile-scanner/"
    
    public init() {}
    
    public func triggerAction() {
        if isEnabled {
            showOverlay()
        }
    }
    
    public func start() {
        KeyboardShortcuts.onKeyDown(for: .mobileScanner) { [weak self] in
            self?.showOverlay()
        }
    }
    
    public func stop() {
        KeyboardShortcuts.disable(.mobileScanner)
        hideOverlay()
    }
    
    public func makeSettingsView() -> AnyView {
        AnyView(MobileScannerSettingsView())
    }
    
    private func showOverlay() {
        hideOverlay()
        
        let window = MobileScannerOverlayWindow()
        self.overlayWindow = window
        
        // Start engine
        engine = WebRTCEngine()
        engine?.delegate = self
        engine?.startReceiving()
        
        updateOverlayUI(roomID: nil)
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func hideOverlay() {
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        engine?.stopReceiving()
        engine = nil
    }
    
    private func updateOverlayUI(roomID: String?) {
        guard let window = overlayWindow else { return }
        
        let view = MobileScannerOverlayView(
            roomID: roomID,
            githubPagesURL: githubPagesURL,
            onClose: { [weak self] in
                self?.hideOverlay()
            }
        )
        
        window.contentView = NSHostingView(rootView: view)
    }
    
    // MARK: - WebRTCEngineDelegate
    func webRTCEngine(_ engine: WebRTCEngine, didGenerateRoomID roomID: String) {
        updateOverlayUI(roomID: roomID)
    }
    
    func webRTCEngine(_ engine: WebRTCEngine, didReceivePayload payload: String) {
        // Success!
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload, forType: .string)
        NSSound(named: "Purr")?.play()
        
        // Auto-close after receiving
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.hideOverlay()
        }
    }
    
    func webRTCEngine(_ engine: WebRTCEngine, didEncounterError error: String) {
        print("WebRTC Error: \(error)")
    }
}

extension KeyboardShortcuts.Name: @retroactive @unchecked Sendable {}

public extension KeyboardShortcuts.Name {
    static let mobileScanner = Self("mobileScanner", default: .init(.m, modifiers: [.command, .shift]))
}

struct MobileScannerSettingsView: View {
    @AppStorage("mobileScannerGithubURL") private var githubPagesURL: String = "https://sagarbangade.github.io/mactoys-mobile-scanner/"
    
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Shortcut:", name: .mobileScanner)
            
            Section(header: Text("Configuration")) {
                TextField("GitHub Pages URL", text: $githubPagesURL)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Text("This must point to the folder where you host MobileScannerWeb/index.html")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}
