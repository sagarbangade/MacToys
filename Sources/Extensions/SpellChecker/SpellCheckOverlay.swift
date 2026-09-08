import Foundation
import AppKit
import ApplicationServices

/// Draws red wavy underlines beneath misspelled words by placing a
/// transparent overlay window over the focused text field.
@MainActor
final class SpellCheckOverlay {
    static let shared = SpellCheckOverlay()

    private var overlayWindow: NSWindow?
    private var underlineView: UnderlineView?
    private var windowObserver: Any?

    private init() {}

    func update(words: [MisspelledWord], element: AXUIElement) {
        guard !words.isEmpty else {
            clearAll()
            return
        }

        // Get the element's frame to position our overlay
        guard let elementFrame = frameOf(element) else {
            clearAll()
            return
        }

        let screenHeight = NSScreen.screens.first?.frame.height ?? 0

        // Convert AX frame (top-left origin) to AppKit frame (bottom-left origin)
        let appKitFrame = CGRect(
            x: elementFrame.origin.x,
            y: screenHeight - elementFrame.origin.y - elementFrame.height,
            width: elementFrame.width,
            height: elementFrame.height
        )

        // Convert each word's bounds from AX coords to local overlay coords
        var localWords: [(rect: CGRect, word: MisspelledWord)] = []
        for word in words {
            let localX = word.screenBounds.origin.x - elementFrame.origin.x
            let localY = word.screenBounds.origin.y - elementFrame.origin.y
            let localRect = CGRect(
                x: localX,
                y: localY,
                width: word.screenBounds.width,
                height: word.screenBounds.height
            )
            localWords.append((localRect, word))
        }

        if overlayWindow == nil {
            createOverlayWindow()
        }

        guard let window = overlayWindow, let view = underlineView else { return }

        view.wordRects = localWords.map { $0.rect }
        view.needsDisplay = true

        window.setFrame(NSRect(origin: appKitFrame.origin, size: appKitFrame.size), display: true)
        window.orderFrontRegardless()
    }

    func clearAll() {
        overlayWindow?.orderOut(nil)
        underlineView?.wordRects = []
        underlineView?.needsDisplay = true
    }

    private func createOverlayWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.animationBehavior = .none

        let view = UnderlineView(frame: .zero)
        view.autoresizingMask = [.width, .height]
        window.contentView = view

        self.overlayWindow = window
        self.underlineView = view
    }

    private func frameOf(_ element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionValue = positionRef,
              let sizeValue = sizeRef,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }
}

// MARK: - Underline Drawing View

/// Custom NSView that draws red wavy underlines at specified positions.
final class UnderlineView: NSView {
    var wordRects: [CGRect] = []

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard !wordRects.isEmpty else { return }

        let underlineColor = NSColor.systemRed.withAlphaComponent(0.85)
        underlineColor.setStroke()

        for wordRect in wordRects {
            // Convert from top-left coords (AX) to bottom-left (AppKit NSView)
            let flippedY = bounds.height - wordRect.origin.y - wordRect.height
            let baselineY = flippedY - 1 // Just below the text
            let startX = wordRect.origin.x
            let endX = startX + wordRect.width

            // Draw a wavy/squiggly underline
            let path = NSBezierPath()
            path.lineWidth = 1.5
            path.lineCapStyle = .round

            let waveHeight: CGFloat = 2.0
            let waveLength: CGFloat = 4.0
            var x = startX

            path.move(to: NSPoint(x: x, y: baselineY))

            while x < endX {
                let nextX = min(x + waveLength, endX)
                let controlX = x + waveLength / 2
                let controlY = baselineY + (Int((x - startX) / waveLength) % 2 == 0 ? waveHeight : -waveHeight)
                path.curve(to: NSPoint(x: nextX, y: baselineY),
                           controlPoint1: NSPoint(x: controlX, y: controlY),
                           controlPoint2: NSPoint(x: controlX, y: controlY))
                x = nextX
            }

            path.stroke()
        }
    }

    override var isFlipped: Bool { false }
}
