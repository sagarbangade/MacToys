import Foundation
import ScreenCaptureKit
import Vision
import Cocoa

@MainActor
public final class QREngine {
    public static func captureAndScan(rect: CGRect, display: SCDisplay, screenBounds: CGRect, shareableContent: SCShareableContent) async throws -> String {
        let currentPID = NSRunningApplication.current.processIdentifier
        let appsToExclude = shareableContent.applications.filter { $0.processID == currentPID }
        let filter = SCContentFilter(display: display, excludingApplications: appsToExclude, exceptingWindows: [])
        let config = SCStreamConfiguration()
        
        config.width = display.width
        config.height = display.height
        config.showsCursor = false
        
        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        
        let normalizedRect = CGRect(
            x: rect.origin.x / screenBounds.width,
            y: rect.origin.y / screenBounds.height,
            width: rect.width / screenBounds.width,
            height: rect.height / screenBounds.height
        )
        
        return try await scanQR(in: cgImage, regionOfInterest: normalizedRect)
    }
    
    private static func scanQR(in image: CGImage, regionOfInterest: CGRect) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectBarcodesRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNBarcodeObservation] else {
                    continuation.resume(returning: "")
                    return
                }
                
                let payloads = observations.compactMap { $0.payloadStringValue }
                continuation.resume(returning: payloads.joined(separator: "\n"))
            }
            
            // Allow detecting standard formats (QR, Aztec, PDF417, UPCE, etc)
            request.symbologies = [.qr, .aztec, .pdf417, .dataMatrix, .upce, .ean13, .code39, .code128]
            
            let clampedRect = CGRect(
                x: max(0, min(1, regionOfInterest.origin.x)),
                y: max(0, min(1, regionOfInterest.origin.y)),
                width: max(0, min(1 - max(0, regionOfInterest.origin.x), regionOfInterest.width)),
                height: max(0, min(1 - max(0, regionOfInterest.origin.y), regionOfInterest.height))
            )
            request.regionOfInterest = clampedRect
            
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
