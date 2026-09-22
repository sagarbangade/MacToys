import Cocoa
import ApplicationServices
import SwiftUI

struct SquiggleData {
    var screenRect: CGRect
    var correctedSentence: String
    var window: NSWindow
}

@MainActor
public class GrammarOverlayManager {
    public static let shared = GrammarOverlayManager()
    
    private var timer: Timer?
    private var lastCheckedText: String = ""
    private var lastFocusedElement: AXUIElement?
    private var isChecking = false
    
    private var activeSquiggles: [SquiggleData] = []
    
    // Hover Popup
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var popupWindow: NSWindow?
    private var isPopupVisible = false
    
    private init() {}
    
    public func start() {
        print("[GrammarOverlayManager] Starting accessibility polling...")
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkFocusedElement()
            }
        }
        
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.handleMouseMoved()
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.handleMouseMoved()
            return event
        }
    }
    
    public func stop() {
        timer?.invalidate()
        timer = nil
        
        if let gm = globalMouseMonitor { NSEvent.removeMonitor(gm) }
        if let lm = localMouseMonitor { NSEvent.removeMonitor(lm) }
        globalMouseMonitor = nil
        localMouseMonitor = nil
        
        clearOverlay()
        hidePopup()
    }
    
    private func handleMouseMoved() {
        let location = NSEvent.mouseLocation // Global bottom-left coords
        var hoveredData: SquiggleData? = nil
        
        for data in activeSquiggles {
            let hitBox = data.screenRect.insetBy(dx: -15, dy: -15) // Generous hit area
            if hitBox.contains(location) {
                hoveredData = data
                break
            }
        }
        
        // Also keep popup visible if mouse is inside the popup itself
        if let popup = popupWindow, popup.isVisible {
            if popup.frame.contains(location) {
                return
            }
        }
        
        if let data = hoveredData {
            showPopup(for: data)
        } else {
            hidePopup()
        }
    }
    
    private func showPopup(for data: SquiggleData) {
        if isPopupVisible && popupWindow?.title == data.correctedSentence { return }
        
        if popupWindow == nil {
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .floating + 1
            window.hasShadow = false
            self.popupWindow = window
        }
        
        let view = HoverPopupView(correctedText: data.correctedSentence) { [weak self] in
            self?.applyFix(correctedText: data.correctedSentence)
        }
        
        let hostingView = NSHostingView(rootView: view)
        popupWindow?.contentView = hostingView
        popupWindow?.title = data.correctedSentence // Store the text as title to avoid re-rendering same state
        
        // Size it
        let targetSize = hostingView.fittingSize
        
        // Position it above the squiggle
        let popupX = data.screenRect.midX - (targetSize.width / 2)
        let popupY = data.screenRect.maxY + 10
        let frame = CGRect(x: popupX, y: popupY, width: targetSize.width, height: targetSize.height)
        
        popupWindow?.setFrame(frame, display: true)
        popupWindow?.orderFront(nil)
        isPopupVisible = true
    }
    
    private func hidePopup() {
        if isPopupVisible {
            popupWindow?.orderOut(nil)
            isPopupVisible = false
        }
    }
    
    private func applyFix(correctedText: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(correctedText, forType: .string)
        
        // Hide overlay and reset so it scans fresh
        hidePopup()
        clearOverlay()
        lastCheckedText = "" 
        
        print("[GrammarOverlayManager] Copied to clipboard: \(correctedText)")
    }
    
    private func extractTextAndOffset(from element: AXUIElement) -> (String, Int)? {
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success, let val = valueRef {
            if CFGetTypeID(val) == CFStringGetTypeID() {
                return (val as! String, 0)
            } else if CFGetTypeID(val) == CFAttributedStringGetTypeID() {
                return (CFAttributedStringGetString(val as! CFAttributedString)! as String, 0)
            }
        }
        
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success, let rangeVal = rangeRef {
            var range = CFRange()
            AXValueGetValue(rangeVal as! AXValue, .cfRange, &range)
            
            let start = max(0, range.location - 200)
            let length = 400
            var textRange = CFRange(location: start, length: length)
            let textRangeVal = AXValueCreate(.cfRange, &textRange)!
            
            var stringRef: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, textRangeVal, &stringRef) == .success, let stringVal = stringRef as? String {
                return (stringVal, start)
            }
        }
        
        return nil
    }
    
    private func findErrorRanges(original: String, corrected: String) -> [NSRange] {
        var errorRanges: [NSRange] = []
        let origWords = original.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let corrWords = corrected.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        
        if original == corrected { return [] }
        
        let diff = corrWords.difference(from: origWords)
        var wrongWords: [String] = []
        for change in diff {
            switch change {
            case .remove(_, let element, _):
                wrongWords.append(element)
            case .insert: break
            }
        }
        
        var searchStartIndex = original.startIndex
        for word in origWords {
            if let range = original.range(of: word, range: searchStartIndex..<original.endIndex) {
                if wrongWords.contains(word) {
                    errorRanges.append(NSRange(range, in: original))
                    if let idx = wrongWords.firstIndex(of: word) {
                        wrongWords.remove(at: idx)
                    }
                }
                searchStartIndex = range.upperBound
            }
        }
        return errorRanges
    }
    
    private func checkFocusedElement() async {
        guard !isChecking else { return }
        
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        
        guard err == .success, let element = focusedRef as! AXUIElement? else {
            self.clearOverlay()
            return
        }
        
        guard let (currentText, globalOffset) = extractTextAndOffset(from: element) else {
            self.clearOverlay()
            return
        }
        
        if currentText.isEmpty || currentText.count < 5 {
            self.clearOverlay()
            return
        }
        
        if currentText == lastCheckedText {
            return
        }
        
        lastCheckedText = currentText
        lastFocusedElement = element
        isChecking = true
        
        do {
            let sentences = currentText.components(separatedBy: .init(charactersIn: ".!?\n"))
            if let lastSentence = sentences.last(where: { $0.trimmingCharacters(in: .whitespaces).count > 5 }) {
                let trimmed = lastSentence.trimmingCharacters(in: .whitespaces)
                let corrected = try await GECSidecar.shared.correct(text: trimmed, instruction: "")
                
                if corrected.trimmingCharacters(in: .whitespacesAndNewlines) != trimmed {
                    if let sentenceRange = currentText.range(of: trimmed) {
                        let nsSentenceRange = NSRange(sentenceRange, in: currentText)
                        let sentenceGlobalOffset = globalOffset + nsSentenceRange.location
                        let errorRanges = findErrorRanges(original: trimmed, corrected: corrected)
                        
                        var newSquiggles: [SquiggleData] = []
                        let primaryScreenHeight = CGDisplayBounds(CGMainDisplayID()).height
                        
                        for wordRange in errorRanges {
                            let globalWordLocation = sentenceGlobalOffset + wordRange.location
                            var cfRange = CFRange(location: globalWordLocation, length: wordRange.length)
                            let rangeValue = AXValueCreate(.cfRange, &cfRange)!
                            
                            var boundsRef: CFTypeRef?
                            if AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &boundsRef) == .success, let boundsVal = boundsRef {
                                var rect = CGRect.zero
                                AXValueGetValue(boundsVal as! AXValue, .cgRect, &rect)
                                
                                let yAppKit = primaryScreenHeight - rect.origin.y - rect.height
                                let squiggleHeight: CGFloat = 6
                                let windowFrame = CGRect(x: rect.origin.x, y: yAppKit - squiggleHeight, width: rect.width, height: squiggleHeight)
                                
                                let window = NSWindow(
                                    contentRect: windowFrame,
                                    styleMask: [.borderless],
                                    backing: .buffered,
                                    defer: false
                                )
                                window.isOpaque = false
                                window.backgroundColor = .clear
                                window.level = .floating
                                window.ignoresMouseEvents = true
                                window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
                                window.contentView = NSHostingView(rootView: SquiggleView(width: rect.width, height: squiggleHeight))
                                
                                window.orderFront(nil)
                                
                                let data = SquiggleData(screenRect: windowFrame, correctedSentence: corrected, window: window)
                                newSquiggles.append(data)
                            }
                        }
                        
                        self.clearOverlay()
                        self.activeSquiggles = newSquiggles
                    }
                } else {
                    self.clearOverlay()
                }
            }
        } catch {
            print("[GrammarOverlayManager] AI check failed: \(error)")
        }
        
        isChecking = false
    }
    
    private func clearOverlay() {
        for data in activeSquiggles {
            data.window.orderOut(nil)
        }
        activeSquiggles.removeAll()
    }
}

struct SquiggleView: View {
    var width: CGFloat
    var height: CGFloat
    
    var body: some View {
        SquiggleLine()
            .stroke(Color.red, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .frame(width: width, height: height)
    }
}

struct SquiggleLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let amplitude: CGFloat = 1.5
        let frequency: CGFloat = 4.0
        
        path.move(to: CGPoint(x: 0, y: rect.midY))
        for x in stride(from: 0, through: rect.width, by: 1) {
            let y = rect.midY + amplitude * sin(x / frequency)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        return path
    }
}

struct HoverPopupView: View {
    var correctedText: String
    var onFix: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Text(correctedText)
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .lineLimit(3)
            
            Button(action: onFix) {
                Text("Copy Fix")
                    .bold()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.3), radius: 5, x: 0, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        )
        // Ensure the SwiftUI view registers hover events to stay alive
        .onHover { _ in }
    }
}
