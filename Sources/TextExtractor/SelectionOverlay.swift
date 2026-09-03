import Cocoa
import ScreenCaptureKit

@MainActor
class SelectionOverlayWindow: NSWindow {
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
class SelectionView: NSView {
    var startPoint: NSPoint?
    var currentPoint: NSPoint?
    
    var onSelectionComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        
        // Add a tracking area to change cursor to crosshair
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
        // Dim the background
        NSColor(white: 0.0, alpha: 0.3).setFill()
        dirtyRect.fill()
        
        // Draw the selection rectangle cutout
        if let start = startPoint, let current = currentPoint {
            let rect = NSRect(
                x: min(start.x, current.x),
                y: min(start.y, current.y),
                width: abs(current.x - start.x),
                height: abs(current.y - start.y)
            )
            
            NSGraphicsContext.current?.cgContext.setBlendMode(.clear)
            NSColor.clear.setFill()
            rect.fill()
            
            NSGraphicsContext.current?.cgContext.setBlendMode(.normal)
            NSColor.white.setStroke()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = 1.0
            path.stroke()
        } else {
            // Draw instruction text when not measuring
            let instruction = "Click and drag to extract text  •  Press ESC to cancel"
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
        }
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
        guard let start = startPoint, let current = currentPoint else {
            onCancel?()
            return
        }
        
        let rect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        
        // Only trigger if a reasonably sized box was drawn
        if rect.width > 5 && rect.height > 5 {
            onSelectionComplete?(rect)
        } else {
            onCancel?()
        }
        
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
