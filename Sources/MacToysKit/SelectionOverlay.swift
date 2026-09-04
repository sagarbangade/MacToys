import Cocoa

@MainActor
public class SelectionOverlayWindow: NSWindow {
    public init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless], backing: .buffered, defer: false)
        self.isOpaque = false
        self.backgroundColor = NSColor.clear
        self.level = .screenSaver
        self.ignoresMouseEvents = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.hasShadow = false
    }
    
    public override var canBecomeKey: Bool { return true }
    public override var canBecomeMain: Bool { return true }
}

@MainActor
public class SelectionView: NSView {
    public var startPoint: NSPoint?
    public var currentPoint: NSPoint?
    
    public var onSelectionComplete: ((CGRect) -> Void)?
    public var onCancel: (() -> Void)?
    public var instructionText: String = "Click and drag to select  •  Press ESC to cancel"
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        
        let trackingArea = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved], owner: self, userInfo: nil)
        self.addTrackingArea(trackingArea)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.0, alpha: 0.3).setFill()
        dirtyRect.fill()
        
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
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14, weight: .medium),
                .foregroundColor: NSColor.white
            ]
            let attrString = NSAttributedString(string: instructionText, attributes: attributes)
            let textSize = attrString.size()
            
            let padding: CGFloat = 8.0
            let labelRect = NSRect(
                x: (bounds.width - textSize.width) / 2 - padding,
                y: bounds.height - 60,
                width: textSize.width + padding * 2,
                height: textSize.height + padding * 2
            )
            
            let bgPath = NSBezierPath(roundedRect: labelRect, xRadius: 6, yRadius: 6)
            NSColor(white: 0.0, alpha: 0.6).setFill()
            bgPath.fill()
            
            attrString.draw(at: NSPoint(x: labelRect.minX + padding, y: labelRect.minY + padding))
        }
    }
    
    public override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }
    
    public override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }
    
    public override func mouseUp(with event: NSEvent) {
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
        
        if rect.width > 5 && rect.height > 5 {
            onSelectionComplete?(rect)
        } else {
            onCancel?()
        }
        
        startPoint = nil
        currentPoint = nil
        needsDisplay = true
    }
    
    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        }
    }
}
