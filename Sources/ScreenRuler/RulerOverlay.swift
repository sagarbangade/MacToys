import Cocoa
import SwiftUI

@MainActor
class RulerOverlayWindow: NSWindow {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless], backing: .buffered, defer: false)
        self.isOpaque = false
        self.backgroundColor = NSColor.clear
        self.level = .screenSaver
        self.ignoresMouseEvents = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.hasShadow = false
    }
    
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
}

@MainActor
class RulerView: NSView {
    var startPoint: NSPoint?
    var currentPoint: NSPoint?
    
    var onCancel: (() -> Void)?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        
        let trackingArea = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved], owner: self, userInfo: nil)
        self.addTrackingArea(trackingArea)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }
    
    override func draw(_ dirtyRect: NSRect) {
        // Dim the background slightly
        NSColor(white: 0.0, alpha: 0.1).setFill()
        dirtyRect.fill()
        
        guard let start = startPoint, let current = currentPoint else {
            // Draw instruction text when not measuring
            let instruction = "Click and drag to measure  •  Press ESC to close"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14, weight: .medium),
                .foregroundColor: NSColor.white
            ]
            let attrString = NSAttributedString(string: instruction, attributes: attributes)
            let textSize = attrString.size()
            
            let padding: CGFloat = 8.0
            let labelRect = NSRect(
                x: (bounds.width - textSize.width) / 2 - padding,
                y: bounds.height - 60, // Top center
                width: textSize.width + padding * 2,
                height: textSize.height + padding * 2
            )
            
            let bgPath = NSBezierPath(roundedRect: labelRect, xRadius: 6, yRadius: 6)
            NSColor(white: 0.0, alpha: 0.6).setFill()
            bgPath.fill()
            
            attrString.draw(at: NSPoint(x: labelRect.minX + padding, y: labelRect.minY + padding))
            return
        }
        
        let rect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        
        // Draw the measurement rectangle
        NSColor.systemBlue.withAlphaComponent(0.2).setFill()
        rect.fill()
        
        NSColor.systemBlue.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1.0
        path.stroke()
        
        // Draw the measurement label
        let widthStr = String(format: "%.0f", rect.width)
        let heightStr = String(format: "%.0f", rect.height)
        let text = "\(widthStr) × \(heightStr)"
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attrString.size()
        
        let padding: CGFloat = 4.0
        let labelRect = NSRect(
            x: current.x + 10,
            y: current.y - textSize.height - 10 - padding * 2,
            width: textSize.width + padding * 2,
            height: textSize.height + padding * 2
        )
        
        // Ensure label stays within screen bounds
        var finalLabelRect = labelRect
        if finalLabelRect.maxX > bounds.maxX {
            finalLabelRect.origin.x = current.x - finalLabelRect.width - 10
        }
        if finalLabelRect.minY < bounds.minY {
            finalLabelRect.origin.y = current.y + 10
        }
        
        let bgPath = NSBezierPath(roundedRect: finalLabelRect, xRadius: 4, yRadius: 4)
        NSColor.systemBlue.setFill()
        bgPath.fill()
        
        attrString.draw(at: NSPoint(x: finalLabelRect.minX + padding, y: finalLabelRect.minY + padding))
    }
    
    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }
    
    override func mouseUp(with event: NSEvent) {
        // Optional: Keep it on screen until they press escape or click elsewhere
        // For now, let's reset it so they can measure another area, unless they press Escape to exit.
        // Actually, many rulers leave the box there so you can read it. Let's leave it.
    }
    
    override func rightMouseDown(with event: NSEvent) {
        // Clear on right click
        startPoint = nil
        currentPoint = nil
        needsDisplay = true
    }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCancel?()
        }
    }
}
