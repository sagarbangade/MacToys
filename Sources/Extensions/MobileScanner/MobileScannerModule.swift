import Foundation
import Cocoa
import SwiftUI
import MacToysKit
import TextExtractor
@preconcurrency import KeyboardShortcuts

@MainActor
public final class MobileScannerModule: UtilityModule, WebRTCEngineDelegate {
    public let id = "mobileScanner"
    public let displayName = "Mobile Scanner"
    public let description = "Scan real-world text with your phone and beam it to Mac"
    public let iconSymbol = "iphone.and.arrow.forward"
    
    public var isEnabled: Bool = false
    public let requiredPermissions: [PermissionRequirement] = []
    public var shortcutName: KeyboardShortcuts.Name? { .mobileScanner }
    
    private var overlayWindow: MobileScannerOverlayWindow?
    private var engine: WebRTCEngine?
    
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
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload, forType: .string)
        NSSound(named: "Purr")?.play()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.hideOverlay()
        }
    }
    
    func webRTCEngine(_ engine: WebRTCEngine, didReceiveOCRImage base64String: String) {
        let components = base64String.components(separatedBy: ",")
        let cleanBase64 = components.count > 1 ? components[1] : base64String
        
        guard let data = Data(base64Encoded: cleanBase64, options: .ignoreUnknownCharacters),
              let nsImage = NSImage(data: data),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("Failed to decode image from WebRTC")
            return
        }
        
        Task {
            do {
                let text = try await OCREngine.recognizeText(in: cgImage)
                if !text.isEmpty {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    NSSound(named: "Glass")?.play()
                    self.hideOverlay()
                } else {
                    print("OCR found no text")
                    NSSound(named: "Basso")?.play()
                }
            } catch {
                print("OCR Error: \(error)")
                NSSound(named: "Basso")?.play()
            }
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
            }
        }
        .padding()
    }
}
