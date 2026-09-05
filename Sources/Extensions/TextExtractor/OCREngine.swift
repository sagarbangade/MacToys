import Foundation
import ScreenCaptureKit
import Vision
import Cocoa

@MainActor
public final class OCREngine {
    public static func captureAndRecognize(rect: CGRect, display: SCDisplay, screenBounds: CGRect, shareableContent: SCShareableContent) async throws -> String {
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
        
        return try await recognizeText(in: cgImage, regionOfInterest: normalizedRect)
    }
    
    public static func recognizeText(in image: CGImage, regionOfInterest: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }
                
                let sortedObservations = observations.sorted { a, b in
                    let yDiff = abs(a.boundingBox.minY - b.boundingBox.minY)
                    if yDiff < 0.02 {
                        return a.boundingBox.minX < b.boundingBox.minX
                    }
                    return a.boundingBox.minY > b.boundingBox.minY 
                }
                
                let recognizedStrings = sortedObservations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }
                
                continuation.resume(returning: recognizedStrings.joined(separator: "\n"))
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
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
