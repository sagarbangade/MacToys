import Foundation
import Cocoa
import SwiftUI
import MacToysKit
import ScreenCaptureKit
@preconcurrency import KeyboardShortcuts

@MainActor
public final class QRScannerModule: UtilityModule {
    public let id = "qrScanner"
    public let displayName = "QR Scanner"
    public let description = "Scan QR codes and barcodes from any screen region"
    public let iconSymbol = "qrcode.viewfinder"
    
    public var isEnabled: Bool = false
    public let requiredPermissions: [PermissionRequirement] = [.screenRecording]
    public var shortcutName: KeyboardShortcuts.Name? { .qrScanner }
    
    private var windows: [NSWindow] = []
    
    public init() {}
    
    public func triggerAction() {
        if isEnabled {
            showOverlays()
        }
    }
    
    public func start() {
        KeyboardShortcuts.onKeyDown(for: .qrScanner) { [weak self] in
            self?.showOverlays()
        }
    }
    
    public func stop() {
        KeyboardShortcuts.disable(.qrScanner)
        hideOverlays()
    }
    
    public func makeSettingsView() -> AnyView {
        AnyView(QRScannerSettingsView())
    }
    
    private func showOverlays() {
        hideOverlays()
        
        for screen in NSScreen.screens {
            let window = SelectionOverlayWindow(contentRect: screen.frame)
            let view = SelectionView(frame: window.contentView!.bounds)
            view.instructionText = "Click and drag to scan a QR Code  •  Press ESC to cancel"
            
            view.onCancel = { [weak self] in
                self?.hideOverlays()
            }
            
            view.onSelectionComplete = { [weak self] rect in
                guard let self = self else { return }
                
                guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                    self.hideOverlays()
                    return
                }
                
                self.hideOverlays()
                
                Task {
                    await self.captureAndScan(rect: rect, displayID: screenNumber, screenBounds: screen.frame)
                }
            }
            
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func hideOverlays() {
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
    }
    
    private func captureAndScan(rect: CGRect, displayID: CGDirectDisplayID, screenBounds: CGRect) async {
        do {
            let shareableContent = try await SCShareableContent.current
            guard let display = shareableContent.displays.first(where: { $0.displayID == displayID }) else { return }
            
            let text = try await QREngine.captureAndScan(rect: rect, display: display, screenBounds: screenBounds, shareableContent: shareableContent)
            
            if !text.isEmpty {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                NSSound(named: "Purr")?.play()
                print("Scanned QR code: \(text)")
            } else {
                NSSound(named: "Basso")?.play()
            }
        } catch {
            print("QR Scan Error: \(error)")
            NSSound(named: "Basso")?.play()
        }
    }
}

extension KeyboardShortcuts.Name: @retroactive @unchecked Sendable {}

public extension KeyboardShortcuts.Name {
    static let qrScanner = Self("qrScanner", default: .init(.q, modifiers: [.command, .shift]))
}

struct QRScannerSettingsView: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Shortcut:", name: .qrScanner)
            Text("Select a region on screen containing a QR code or barcode to extract its data directly to your clipboard.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}
