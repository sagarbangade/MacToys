import Foundation
import Cocoa
import SwiftUI
import MacToysKit
@preconcurrency import KeyboardShortcuts

public enum ColorFormat: String, CaseIterable, Identifiable {
    case hex = "HEX (#FFFFFF)"
    case rgb = "RGB (255, 255, 255)"
    case hsl = "HSL (360, 100%, 100%)"
    case nsColor = "NSColor"
    
    public var id: String { self.rawValue }
}

@MainActor
public final class ColorPickerModule: UtilityModule {
    public let id = "colorPicker"
    public let displayName = "Color Picker"
    public let description = "Pick colors from anywhere on your screen"
    public let iconSymbol = "eyedropper.halffull"
    
    public var isEnabled: Bool = false
    public let requiredPermissions: [PermissionRequirement] = []
    public var shortcutName: KeyboardShortcuts.Name? { .colorPicker }
    
    private let sampler = NSColorSampler()
    private var infoWindow: ColorInfoWindow?
    
    public init() {}
    
    public func triggerAction() {
        if isEnabled {
            pickColor()
        }
    }
    
    public func start() {
        KeyboardShortcuts.onKeyDown(for: .colorPicker) { [weak self] in
            self?.pickColor()
        }
    }
    
    public func stop() {
        KeyboardShortcuts.disable(.colorPicker)
        infoWindow?.close()
    }
    
    public func makeSettingsView() -> AnyView {
        AnyView(ColorPickerSettingsView())
    }
    
    private func pickColor() {
        infoWindow?.close() // Hide if open
        NSApp.activate(ignoringOtherApps: true)
        
        Task {
            if let color = await sampler.sample() {
                self.handlePickedColor(color)
            }
        }
    }
    
    private func handlePickedColor(_ color: NSColor) {
        let formatStr = UserDefaults.standard.string(forKey: "colorPickerFormat") ?? ColorFormat.hex.rawValue
        let format = ColorFormat(rawValue: formatStr) ?? .hex
        
        let resultString: String
        switch format {
        case .hex: resultString = color.toHex() ?? ""
        case .rgb: resultString = color.toRGBString() ?? ""
        case .hsl: resultString = color.toHSLString() ?? ""
        case .nsColor: resultString = color.toNSColorString() ?? ""
        }
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(resultString, forType: .string)
        NSSound(named: "Tink")?.play()
        
        showInfoWindow(for: color)
    }
    
    private func showInfoWindow(for color: NSColor) {
        if infoWindow == nil {
            infoWindow = ColorInfoWindow()
        }
        
        let view = ColorInfoView(color: color) { [weak self] in
            self?.infoWindow?.close()
        }
        
        infoWindow?.contentViewController = NSHostingController(rootView: view)
        
        // Position window near mouse
        let mouseLocation = NSEvent.mouseLocation
        let windowSize = infoWindow!.frame.size
        // Shift it slightly so it doesn't appear directly under cursor
        let newOrigin = NSPoint(x: mouseLocation.x + 20, y: mouseLocation.y - windowSize.height - 20)
        infoWindow?.setFrameOrigin(newOrigin)
        
        infoWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

public extension KeyboardShortcuts.Name {
    static let colorPicker = Self("colorPicker", default: .init(.c, modifiers: [.command, .shift]))
}

struct ColorPickerSettingsView: View {
    @AppStorage("colorPickerFormat") private var selectedFormat: ColorFormat = .hex
    
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Shortcut:", name: .colorPicker)
            
            Picker("Copy Format:", selection: $selectedFormat) {
                ForEach(ColorFormat.allCases) { format in
                    Text(format.rawValue).tag(format)
                }
            }
            
            Text("Press the hotkey to open the magnifying loupe. The selected color will be copied to your clipboard.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}
