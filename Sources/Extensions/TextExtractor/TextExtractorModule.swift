import Foundation
import Cocoa
import SwiftUI
import MacToysKit
import ScreenCaptureKit
@preconcurrency import KeyboardShortcuts

@MainActor
public final class TextExtractorModule: UtilityModule {
    public let id = "textExtractor"
    public let displayName = "Text Extractor"
    public let description = "Extract text from any image or screen region"
    public let iconSymbol = "text.viewfinder"
    
    public var isEnabled: Bool = false
    public let requiredPermissions: [PermissionRequirement] = [.screenRecording]
    public var shortcutName: KeyboardShortcuts.Name? { .textExtractor }
    
    private var windows: [NSWindow] = []
    
    public init() {}
    
    public func triggerAction() {
        if isEnabled {
            showOverlays()
        }
    }
    
    public func start() {
        KeyboardShortcuts.onKeyDown(for: .textExtractor) { [weak self] in
            self?.showOverlays()
        }
    }
    
    public func stop() {
        KeyboardShortcuts.disable(.textExtractor)
        hideOverlays()
    }
    
    public func makeSettingsView() -> AnyView {
        AnyView(TextExtractorSettingsView())
    }
    
    private func showOverlays() {
        hideOverlays()
        
        for screen in NSScreen.screens {
            let window = SelectionOverlayWindow(contentRect: screen.frame)
            let view = SelectionView(frame: window.contentView!.bounds)
            view.instructionText = "Click and drag to extract text  •  Press ESC to cancel"
            
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
                    await self.captureAndOCR(rect: rect, displayID: screenNumber, screenBounds: screen.frame)
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
    
    private func captureAndOCR(rect: CGRect, displayID: CGDirectDisplayID, screenBounds: CGRect) async {
        do {
            let shareableContent = try await SCShareableContent.current
            guard let display = shareableContent.displays.first(where: { $0.displayID == displayID }) else { return }
            
            let text = try await OCREngine.captureAndRecognize(rect: rect, display: display, screenBounds: screenBounds, shareableContent: shareableContent)
            
            if !text.isEmpty {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                NSSound(named: "Purr")?.play()
                print("Extracted text: \(text)")
            } else {
                NSSound(named: "Basso")?.play()
            }
        } catch {
            print("OCR Error: \(error)")
        }
    }
}

extension KeyboardShortcuts.Name: @retroactive @unchecked Sendable {}

public extension KeyboardShortcuts.Name {
    static let textExtractor = Self("textExtractor", default: .init(.t, modifiers: [.command, .shift]))
}

struct TextExtractorSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("ACTIVATION SHORTCUT")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                
                PremiumCard {
                    PremiumRow(
                        icon: "command",
                        iconColor: .blue,
                        title: "Capture Hotkey",
                        subtitle: "Select any screen area to OCR text directly into your clipboard"
                    ) {
                        KeyboardShortcuts.Recorder("", name: .textExtractor)
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("INTELLIGENCE ENGINE")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                
                PremiumCard {
                    PremiumRow(
                        icon: "eye.fill",
                        iconColor: .indigo,
                        title: "Apple Neural OCR",
                        subtitle: "Hardware-accelerated text recognition using Apple Vision Framework"
                    ) {
                        Text("On-Device")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.indigo)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.indigo.opacity(0.15)))
                    }
                }
            }
        }
    }
}
