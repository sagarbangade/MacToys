import Foundation
import ApplicationServices
import AppKit

@MainActor
public class CaretTracker {
    public static let shared = CaretTracker()

    private init() {}

    /// Finds the best available anchor for the suggestion panel.
    ///
    /// `AXBoundsForRange` is not implemented by a number of Chromium, Electron,
    /// terminal, and custom-editor controls. Those apps can still report a focused
    /// element frame, which is a useful fallback. The caller has a final pointer
    /// fallback for apps that expose no usable accessibility geometry at all.
    public func getSuggestionAnchor() -> CGRect? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedElement = focusedRef else {
            return nil
        }
        let element = focusedElement as! AXUIElement

        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let rangeValue = rangeRef {
            var boundsRef: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXBoundsForRangeParameterizedAttribute as CFString,
                rangeValue,
                &boundsRef
            ) == .success,
               let boundsValue = boundsRef,
               let rect = rect(from: boundsValue), !rect.isEmpty {
                return rect
            }
        }

        if let frame = frame(of: element), !frame.isEmpty {
            // The bottom-left of the focused editor is usually closer to active
            // text than its centre and avoids covering the typed content.
            return CGRect(x: frame.minX + 8, y: frame.maxY - 24, width: 2, height: 18)
        }

        return nil
    }

    private func rect(from value: CFTypeRef) -> CGRect? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }

    private func frame(of element: AXUIElement) -> CGRect? {
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
