import Cocoa
import SwiftUI
import CoreImage.CIFilterBuiltins

@MainActor
class MobileScannerOverlayWindow: NSWindow {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        self.isOpaque = false
        self.backgroundColor = NSColor.clear
        self.level = .floating
        self.isMovableByWindowBackground = true
        self.center()
        self.hasShadow = true
    }
    
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
}

struct MobileScannerOverlayView: View {
    let roomID: String?
    let githubPagesURL: String
    let onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Mobile Scanner")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                        .font(.title2)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal)
            .padding(.top)
            
            Text("Scan this QR code with your phone camera to seamlessly beam text to your Mac clipboard.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            if let roomID = roomID {
                let urlString = "\(githubPagesURL)?room=\(roomID)"
                if let qrImage = generateQRCode(from: urlString) {
                    Image(nsImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 250, height: 250)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(12)
                }
                
                Text("Room ID: \(roomID)")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.bottom)
            } else {
                VStack {
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding()
                    Text("Connecting to secure relay...")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .frame(width: 250, height: 250)
            }
        }
        .frame(width: 400, height: 500)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.95))
                .shadow(radius: 20)
        )
    }
    
    private func generateQRCode(from string: String) -> NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        
        guard let outputImage = filter.outputImage else { return nil }
        
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: transform)
        
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: scaledImage.extent.width, height: scaledImage.extent.height))
    }
}
