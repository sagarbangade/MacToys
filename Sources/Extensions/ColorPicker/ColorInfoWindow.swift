import Cocoa
import SwiftUI
import MacToysKit

@MainActor
class ColorInfoWindow: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 400),
            styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.level = .floating
        self.isFloatingPanel = true
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.isMovableByWindowBackground = true
        self.backgroundColor = .clear
        self.hasShadow = true
    }
}

struct ColorInfoView: View {
    let color: NSColor
    let onClose: () -> Void
    
    // Derived values
    var hex: String { color.toHex() ?? "#000000" }
    var rgb: String { color.toRGBString() ?? "rgb(0, 0, 0)" }
    var hsl: String { color.toHSLString() ?? "hsl(0, 0%, 0%)" }
    var nsColorStr: String { color.toNSColorString() ?? "NSColor()" }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Color Swatch
            ZStack(alignment: .topTrailing) {
                Color(color)
                    .frame(height: 120)
                
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white)
                        .font(.title2)
                        .shadow(radius: 2)
                }
                .buttonStyle(PlainButtonStyle())
                .padding()
            }
            
            VStack(alignment: .leading, spacing: 16) {
                // Formats
                VStack(spacing: 8) {
                    FormatRow(label: "HEX", value: hex)
                    FormatRow(label: "RGB", value: rgb)
                    FormatRow(label: "HSL", value: hsl)
                    FormatRow(label: "NSColor", value: nsColorStr)
                }
                
                Divider()
                
                // Contrast Checker
                Text("WCAG Contrast")
                    .font(.headline)
                
                HStack(spacing: 20) {
                    ContrastBox(backgroundColor: .white, foregroundColor: Color(color), label: "White")
                    ContrastBox(backgroundColor: .black, foregroundColor: Color(color), label: "Black")
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

struct FormatRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            
            Text(value)
                .font(.system(.body, design: .monospaced))
            
            Spacer()
            
            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            }) {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(BorderlessButtonStyle())
        }
    }
}

struct ContrastBox: View {
    let backgroundColor: Color
    let foregroundColor: Color
    let label: String
    
    var body: some View {
        VStack {
            Text("Aa")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(foregroundColor)
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(backgroundColor)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3), lineWidth: 1))
            
            Text("vs \(label)")
                .font(.caption)
        }
    }
}

// MARK: - Color Extensions
extension NSColor {
    func toHex() -> String? {
        guard let rgb = usingColorSpace(.deviceRGB) else { return nil }
        return String(format: "#%02X%02X%02X", Int(round(rgb.redComponent * 255)), Int(round(rgb.greenComponent * 255)), Int(round(rgb.blueComponent * 255)))
    }
    
    func toRGBString() -> String? {
        guard let rgb = usingColorSpace(.deviceRGB) else { return nil }
        return "rgb(\(Int(round(rgb.redComponent * 255))), \(Int(round(rgb.greenComponent * 255))), \(Int(round(rgb.blueComponent * 255))))"
    }
    
    func toHSLString() -> String? {
        guard let hsb = usingColorSpace(.deviceRGB) else { return nil }
        let l = (2 - hsb.saturationComponent) * hsb.brightnessComponent / 2
        let s = l < 1 ? hsb.saturationComponent * hsb.brightnessComponent / (l < 0.5 ? l * 2 : 2 - l * 2) : 0
        return "hsl(\(Int(round(hsb.hueComponent * 360))), \(Int(round((s.isNaN ? 0 : s) * 100)))%, \(Int(round(l * 100)))%)"
    }
    
    func toNSColorString() -> String? {
        guard let rgb = usingColorSpace(.deviceRGB) else { return nil }
        return "NSColor(red: \(String(format: "%.3f", rgb.redComponent)), green: \(String(format: "%.3f", rgb.greenComponent)), blue: \(String(format: "%.3f", rgb.blueComponent)), alpha: 1.0)"
    }
}
