import Cocoa
import ApplicationServices
import SwiftUI
import ClipboardManager
import os

private let overlayLog = Logger(subsystem: "com.mactoys", category: "GrammarOverlay")

func debugLog(_ msg: String) {
    overlayLog.info("\(msg, privacy: .public)")
    let line = "\(Date()): \(msg)\n"
    let path = "/tmp/mactoys_overlay_debug.log"
    if let fh = FileHandle(forWritingAtPath: path) {
        fh.seekToEndOfFile()
        fh.write(line.data(using: .utf8)!)
        fh.closeFile()
    } else {
        FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
    }
}

// Bundle IDs we should NOT overlay on (terminals)
private let terminalBundleIDs: Set<String> = [
    "com.apple.Terminal",
    "com.googlecode.iterm2",
    "net.kovidgoyal.kitty",
    "io.alacritty",
    "com.github.wez.wezterm",
    "dev.warp.Warp-Stable",
    "co.zeit.hyper",
    "com.brave.Browser.app.kj.Prompt",
]

// Custom HostingView that accepts clicks immediately (no double-click needed)
class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

struct SquiggleData {
    var screenRect: CGRect          // AppKit bottom-left coords of the squiggle window
    var originalSentence: String    // The bad sentence
    var correctedSentence: String   // The AI-corrected sentence
    var sentenceGlobalOffset: Int   // Character offset in the full text field
    var element: AXUIElement        // The text field AXUIElement
    var window: NSWindow            // The squiggle NSWindow
    var sentenceStartBounds: CGRect // AX top-left coords of first char of sentence
    var sentenceEndBounds: CGRect   // AX top-left coords of last char of sentence
}

@MainActor
public class GrammarOverlayManager {
    public static let shared = GrammarOverlayManager()
    
    private var timer: Timer?
    private var debounceTask: Task<Void, Never>?
    private var lastKnownText: String = ""
    private var lastCheckedText: String = ""
    private var lastFocusedElement: AXUIElement?
    private var lastFieldRect: CGRect = .zero
    private var isChecking = false
    
    private var activeSquiggles: [SquiggleData] = []
    
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var popupPanel: NSPanel?
    private var isPopupVisible = false
    
    private init() {}
    
    public func start() {
        debugLog("[GrammarOverlayManager] Starting accessibility heartbeat...")
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollInput()
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
        debounceTask?.cancel()
        debounceTask = nil
        
        if let gm = globalMouseMonitor { NSEvent.removeMonitor(gm) }
        if let lm = localMouseMonitor { NSEvent.removeMonitor(lm) }
        globalMouseMonitor = nil
        localMouseMonitor = nil
        
        clearOverlay()
        hidePopup()
        InputCornerBadge.shared.hide()
    }
    
    // MARK: - Mouse Hover
    
    private func handleMouseMoved() {
        let location = NSEvent.mouseLocation
        var hoveredData: SquiggleData? = nil
        
        for data in activeSquiggles {
            let hitBox = data.screenRect.insetBy(dx: -15, dy: -15)
            if hitBox.contains(location) {
                hoveredData = data
                break
            }
        }
        
        // Keep popup alive if mouse is inside popup itself
        if let popup = popupPanel, popup.isVisible {
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
    
    // MARK: - Popup UI
    
    private func showPopup(for data: SquiggleData) {
        if isPopupVisible && popupPanel?.title == data.correctedSentence { return }
        
        if popupPanel == nil {
            // NSPanel with .nonactivatingPanel: accepts clicks WITHOUT activating our app
            let panel = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .floating + 1
            panel.hasShadow = false
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = true
            self.popupPanel = panel
        }
        
        let corrected = data.correctedSentence
        let view = HoverPopupView(correctedText: corrected) { [weak self] in
            self?.applyFix(data: data)
        }
        
        let hostingView = ClickThroughHostingView(rootView: view)
        popupPanel?.contentView = hostingView
        popupPanel?.title = corrected
        
        let targetSize = hostingView.fittingSize
        let popupX = data.screenRect.midX - (targetSize.width / 2)
        let popupY = data.screenRect.maxY + 10
        let frame = CGRect(x: popupX, y: popupY, width: targetSize.width, height: targetSize.height)
        
        popupPanel?.setFrame(frame, display: true)
        popupPanel?.orderFront(nil)
        isPopupVisible = true
    }
    
    private func hidePopup() {
        if isPopupVisible {
            popupPanel?.orderOut(nil)
            isPopupVisible = false
        }
    }
    
    // MARK: - Apply Fix (multi-strategy)
    
    private func applyFix(data: SquiggleData) {
        applySentenceFix(
            element: data.element,
            offset: data.sentenceGlobalOffset,
            original: data.originalSentence,
            corrected: data.correctedSentence,
            startBounds: data.sentenceStartBounds,
            endBounds: data.sentenceEndBounds
        )
    }

    public func applySentenceFix(element: AXUIElement, offset: Int, original: String, corrected: String, startBounds: CGRect = .zero, endBounds: CGRect = .zero) {
        debugLog("[GrammarOverlayManager] Apply Fix clicked for: '\(original)' -> '\(corrected)'")
        
        // 1. Get the target application PID from the stored AXUIElement
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let targetApp = NSRunningApplication(processIdentifier: pid)
        
        // 2. Hide our overlay immediately
        hidePopup()
        clearOverlay()
        InputCornerBadge.shared.update(fieldRect: lastFieldRect, state: .clean)
        lastCheckedText = ""
        lastKnownText = ""
        
        // 3. Re-activate the target app
        NSApp.hide(nil)
        if let app = targetApp {
            if #available(macOS 14.0, *) {
                NSApp.yieldActivation(to: app)
            }
            app.activate(options: .activateIgnoringOtherApps)
        }
        
        // 4. Wait for focus to settle, then try to select & paste
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            // Strategy A: Try AX-based selection
            let len = original.utf16.count
            var cfRange = CFRange(location: offset, length: len)
            let rangeValue = AXValueCreate(.cfRange, &cfRange)!
            let selectErr = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue)
            
            if selectErr == .success {
                debugLog("[GrammarOverlayManager] AX selection succeeded, pasting...")
                self?.pasteText(corrected)
                return
            }
            
            debugLog("[GrammarOverlayManager] AX selection failed (\(selectErr.rawValue)), trying click-based selection...")
            
            // Strategy B: Click-based selection using screen coordinates
            if startBounds != .zero && endBounds != .zero {
                let startClickPoint = CGPoint(x: startBounds.origin.x, y: startBounds.midY)
                let endClickPoint = CGPoint(x: endBounds.maxX, y: endBounds.midY)
                
                self?.clickToSelect(start: startClickPoint, end: endClickPoint) {
                    self?.pasteText(corrected)
                }
            }
        }
    }
    
    /// Clicks at `start`, then shift-clicks at `end` to create a text selection.
    /// Coordinates are in CG (top-left origin) coordinate space.
    private func clickToSelect(start: CGPoint, end: CGPoint, completion: @escaping () -> Void) {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents], state: .eventSuppressionStateSuppressionInterval)
        
        // Click at start position
        let mouseDown = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left)
        let mouseUp = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: start, mouseButton: .left)
        mouseDown?.post(tap: .cgAnnotatedSessionEventTap)
        mouseUp?.post(tap: .cgAnnotatedSessionEventTap)
        
        // Small delay, then shift-click at end position to select
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let shiftSource = CGEventSource(stateID: .combinedSessionState)
            shiftSource?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents], state: .eventSuppressionStateSuppressionInterval)
            
            let shiftDown = CGEvent(mouseEventSource: shiftSource, mouseType: .leftMouseDown, mouseCursorPosition: end, mouseButton: .left)
            shiftDown?.flags = .maskShift
            let shiftUp = CGEvent(mouseEventSource: shiftSource, mouseType: .leftMouseUp, mouseCursorPosition: end, mouseButton: .left)
            shiftUp?.flags = .maskShift
            
            shiftDown?.post(tap: .cgAnnotatedSessionEventTap)
            shiftUp?.post(tap: .cgAnnotatedSessionEventTap)
            
            // Wait for selection to register, then paste
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                completion()
            }
        }
    }
    
    /// Paste text using Cmd+V — mirrors GrammarCheckerService.pasteText exactly
    private func pasteText(_ text: String) {
        ClipboardWatcher.isPaused = true
        
        let pasteboard = NSPasteboard.general
        let oldString = pasteboard.string(forType: .string)
        let needsRestore = (oldString != nil)
        
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents], state: .eventSuppressionStateSuppressionInterval)
        
        let vKeyCode: CGKeyCode = 9
        let cmdV_down = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        cmdV_down?.flags = .maskCommand
        let cmdV_up = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        cmdV_up?.flags = .maskCommand
        
        cmdV_down?.post(tap: .cgAnnotatedSessionEventTap)
        cmdV_up?.post(tap: .cgAnnotatedSessionEventTap)
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
            if needsRestore {
                let pb = NSPasteboard.general
                pb.clearContents()
                if let str = oldString {
                    pb.setString(str, forType: .string)
                }
            }
            DispatchQueue.main.async {
                ClipboardWatcher.shared.syncChangeCount()
                ClipboardWatcher.isPaused = false
                ClipboardWatcher.shared.ignore(text)
                if let str = oldString {
                    ClipboardWatcher.shared.ignore(str)
                }
            }
        }
        
        debugLog("[GrammarOverlayManager] Paste completed!")
    }
    
    // MARK: - Text Extraction
    
    private func extractTextAndOffset(from element: AXUIElement) -> (String, Int)? {
        // Strategy 1: Standard kAXValueAttribute
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success, let val = valueRef {
            var str: String?
            if CFGetTypeID(val) == CFStringGetTypeID() {
                str = val as? String
            } else if CFGetTypeID(val) == CFAttributedStringGetTypeID() {
                str = CFAttributedStringGetString(val as! CFAttributedString) as String
            }
            if let str = str, !str.isEmpty, !isKnownPlaceholder(str) {
                return (str, 0)
            }
        }
        
        // Strategy 2: Query AXNumberOfCharacters if supported (Chromium / WebKit)
        var totalChars: Int? = nil
        var numCharsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXNumberOfCharacters" as CFString, &numCharsRef) == .success,
           let count = numCharsRef as? Int, count > 0 {
            totalChars = count
        }
        
        // Strategy 3: Cursor position + dynamic chunk read
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success, let rangeVal = rangeRef {
            var range = CFRange()
            AXValueGetValue(rangeVal as! AXValue, .cfRange, &range)
            
            let start = max(0, range.location - 500)
            let maxAvailable = totalChars.map { max(0, $0 - start) } ?? max(100, range.location + range.length - start)
            var attemptLengths = [min(1000, maxAvailable), 500, 250, 100, 50, 20]
            if let total = totalChars {
                attemptLengths.insert(total, at: 0)
            }
            
            for len in attemptLengths {
                guard len > 0 else { continue }
                var textRange = CFRange(location: start, length: len)
                let textRangeVal = AXValueCreate(.cfRange, &textRange)!
                
                var stringRef: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, textRangeVal, &stringRef) == .success,
                   let stringVal = stringRef as? String, !stringVal.isEmpty, !isKnownPlaceholder(stringVal) {
                    return (stringVal, start)
                }
            }
        }
        
        // Strategy 4: Full range from 0 to totalChars if cursor was unavailable
        if let total = totalChars, total > 0 {
            var textRange = CFRange(location: 0, length: total)
            let textRangeVal = AXValueCreate(.cfRange, &textRange)!
            var stringRef: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, textRangeVal, &stringRef) == .success,
               let stringVal = stringRef as? String, !stringVal.isEmpty, !isKnownPlaceholder(stringVal) {
                return (stringVal, 0)
            }
        }
        
        return nil
    }

    private func isKnownPlaceholder(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let placeholders = [
            "Type a message",
            "Type a new message",
            "Message to",
            "Search",
            "Write a message"
        ]
        return placeholders.contains { trimmed.hasPrefix($0) }
    }
    
    // MARK: - Diffing & Token Alignment
    
    public struct WordDifference {
        public let original: String
        public let corrected: String
        public let range: NSRange
        public let explanation: String
        
        public init(original: String, corrected: String, range: NSRange, explanation: String) {
            self.original = original
            self.corrected = corrected
            self.range = range
            self.explanation = explanation
        }
    }
    
    private func alignTokens(original: String, corrected: String) -> [WordDifference] {
        let origTokens = original.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let corrTokens = corrected.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        
        var origRanges: [NSRange] = []
        var searchStart = original.startIndex
        for token in origTokens {
            if let r = original.range(of: token, range: searchStart..<original.endIndex) {
                origRanges.append(NSRange(r, in: original))
                searchStart = r.upperBound
            }
        }
        
        // Fast path: If token counts match exactly (e.g. 1-to-1 word replacements)
        if origTokens.count == corrTokens.count {
            var results: [WordDifference] = []
            for i in 0..<origTokens.count {
                if origTokens[i] != corrTokens[i] {
                    let orig = origTokens[i]
                    let corr = corrTokens[i]
                    let origClean = orig.trimmingCharacters(in: .punctuationCharacters).lowercased()
                    let corrClean = corr.trimmingCharacters(in: .punctuationCharacters).lowercased()
                    let expl = (origClean == corrClean) ? "Capitalization / Punctuation" : "Spelling / Grammar"
                    results.append(WordDifference(original: orig, corrected: corr, range: origRanges[i], explanation: expl))
                }
            }
            return results
        }
        
        // LCS-based alignment with token-level granularity
        let n = origTokens.count
        let m = corrTokens.count
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        
        for i in 0..<n {
            for j in 0..<m {
                let oClean = origTokens[i].trimmingCharacters(in: .punctuationCharacters).lowercased()
                let cClean = corrTokens[j].trimmingCharacters(in: .punctuationCharacters).lowercased()
                if oClean == cClean && !oClean.isEmpty {
                    dp[i + 1][j + 1] = dp[i][j] + 1
                } else {
                    dp[i + 1][j + 1] = max(dp[i + 1][j], dp[i][j + 1])
                }
            }
        }
        
        var i = n
        var j = m
        var edits: [(origRange: Range<Int>, corrRange: Range<Int>)] = []
        
        while i > 0 || j > 0 {
            let oClean = i > 0 ? origTokens[i - 1].trimmingCharacters(in: .punctuationCharacters).lowercased() : ""
            let cClean = j > 0 ? corrTokens[j - 1].trimmingCharacters(in: .punctuationCharacters).lowercased() : ""
            
            if i > 0 && j > 0 && oClean == cClean && !oClean.isEmpty && origTokens[i - 1] == corrTokens[j - 1] {
                i -= 1
                j -= 1
            } else if i > 0 && j > 0 && oClean == cClean && !oClean.isEmpty {
                edits.append((origRange: (i - 1)..<i, corrRange: (j - 1)..<j))
                i -= 1
                j -= 1
            } else {
                let startI = i
                let startJ = j
                while (i > 0 && (j == 0 || dp[i][j] == dp[i - 1][j])) ||
                      (j > 0 && (i == 0 || dp[i][j] == dp[i][j - 1])) {
                    if i > 0 && (j == 0 || dp[i][j] == dp[i - 1][j]) {
                        i -= 1
                    } else if j > 0 && (i == 0 || dp[i][j] == dp[i][j - 1]) {
                        j -= 1
                    }
                }
                if i == startI && j == startJ {
                    if i > 0 { i -= 1 }
                    if j > 0 { j -= 1 }
                }
                edits.append((origRange: i..<startI, corrRange: j..<startJ))
            }
        }
        edits.reverse()
        
        var results: [WordDifference] = []
        for edit in edits {
            let origChunk: String
            let corrChunk = corrTokens[edit.corrRange].joined(separator: " ")
            let range: NSRange
            
            if !edit.origRange.isEmpty {
                origChunk = origTokens[edit.origRange].joined(separator: " ")
                let firstR = origRanges[edit.origRange.lowerBound]
                let lastR = origRanges[edit.origRange.upperBound - 1]
                range = NSRange(location: firstR.location, length: lastR.location + lastR.length - firstR.location)
            } else {
                let loc = edit.origRange.lowerBound < origRanges.count ? origRanges[edit.origRange.lowerBound].location : (original as NSString).length
                range = NSRange(location: loc, length: 0)
                origChunk = ""
            }
            
            let origClean = origChunk.trimmingCharacters(in: .punctuationCharacters).lowercased()
            let corrClean = corrChunk.trimmingCharacters(in: .punctuationCharacters).lowercased()
            var expl = "Grammar / Spelling suggestion"
            if origClean == corrClean {
                expl = "Capitalization & punctuation"
            } else if !origChunk.isEmpty && !corrChunk.isEmpty && edit.origRange.count == 1 && edit.corrRange.count == 1 {
                expl = "Spelling"
            }
            
            results.append(WordDifference(original: origChunk, corrected: corrChunk, range: range, explanation: expl))
        }
        
        return results
    }
    
    /// Get AX bounds (top-left CG coords) for a character range
    private func getBoundsForRange(element: AXUIElement, location: Int, length: Int) -> CGRect? {
        var cfRange = CFRange(location: location, length: max(1, length))
        let rangeValue = AXValueCreate(.cfRange, &cfRange)!
        var boundsRef: CFTypeRef?
        let err = AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &boundsRef)
        if err == .success, let boundsVal = boundsRef {
            var rect = CGRect.zero
            AXValueGetValue(boundsVal as! AXValue, .cgRect, &rect)
            if rect.width > 0 && rect.height > 0 {
                return rect
            }
        }
        debugLog("[GrammarOverlay] getBoundsForRange failed at loc=\(location) len=\(length) err=\(err.rawValue)")
        return nil
    }
    
    // MARK: - Focused Element Resolution (Universal: Native & Chromium/Electron)
    
    private func getFocusedElement() -> AXUIElement? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let appName = frontApp.localizedName ?? "?"
        let bundleID = frontApp.bundleIdentifier ?? "?"
        
        // Skip terminals
        if let bid = frontApp.bundleIdentifier, terminalBundleIDs.contains(bid) {
            return nil
        }
        
        let axApp = AXUIElementCreateApplication(frontApp.processIdentifier)
        
        // Crucial for Chromium/Electron/WebView2 apps:
        // Chromium disables accessibility tree by default for performance.
        // AXManualAccessibility: works for Electron apps (Slack, VS Code, Discord, Antigravity)
        AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        // AXEnhancedUserInterface: works for ALL Chromium-based apps (Teams WebView2, Chrome, Edge, Arc, Brave)
        AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        
        var focusedRef: CFTypeRef?
        var err = AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        
        // Fall back to systemWide if app-level focus returned no value
        if err != .success || focusedRef == nil {
            let systemWide = AXUIElementCreateSystemWide()
            err = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        }
        
        guard err == .success, let el = focusedRef as! AXUIElement? else {
            debugLog("[GrammarOverlay] getFocusedElement: no focused element in \(appName) (\(bundleID)), err=\(err.rawValue)")
            return nil
        }
        
        // In Chromium/Electron apps, the focused element is often the root AXWebArea.
        // Resolve it to the actual active text input inside the web view!
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""
        if role == "AXWebArea" {
            // Fast path: Chromium implements accessibilityFocusedUIElement on AXWebArea
            // This returns the active inner element in O(1) without recursive tree walk
            var innerFocusedRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXFocusedUIElementAttribute as CFString, &innerFocusedRef) == .success,
               let innerEl = innerFocusedRef as! AXUIElement? {
                var innerRoleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(innerEl, kAXRoleAttribute as CFString, &innerRoleRef)
                let innerRole = innerRoleRef as? String ?? ""
                if innerRole == "AXTextArea" || innerRole == "AXTextField" {
                    debugLog("[GrammarOverlay] Fast-resolved WebArea to \(innerRole) in \(appName)")
                    return innerEl
                }
                debugLog("[GrammarOverlay] WebArea inner focused element is \(innerRole), trying recursive search...")
            }
            
            // Slow fallback: recursive tree search for AXTextArea/AXTextField
            if let activeInput = findActiveInputInWebArea(el) {
                var inputRole: CFTypeRef?
                AXUIElementCopyAttributeValue(activeInput, kAXRoleAttribute as CFString, &inputRole)
                debugLog("[GrammarOverlay] Recursive-resolved WebArea to input: \(inputRole as? String ?? "?") in \(appName)")
                return activeInput
            } else {
                debugLog("[GrammarOverlay] findActiveInputInWebArea returned nil in \(appName)")
            }
        }
        
        return el
    }
    
    private func findActiveInputInWebArea(_ webArea: AXUIElement) -> AXUIElement? {
        var allInputs: [AXUIElement] = []
        collectInputs(from: webArea, list: &allInputs, depth: 0)
        
        if allInputs.isEmpty { return nil }
        if allInputs.count == 1 { return allInputs.first }
        
        // 1. Prefer an input with AXFocused == true
        for inp in allInputs {
            var isFocRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(inp, kAXFocusedAttribute as CFString, &isFocRef) == .success,
               let isFoc = isFocRef as? Bool, isFoc {
                return inp
            }
        }
        
        // 2. Prefer an input with non-empty text that is not a placeholder
        for inp in allInputs {
            var valRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(inp, kAXValueAttribute as CFString, &valRef) == .success,
               let s = valRef as? String, !s.isEmpty, !isKnownPlaceholder(s) {
                return inp
            }
        }
        
        return allInputs.first
    }
    
    private func collectInputs(from element: AXUIElement, list: inout [AXUIElement], depth: Int) {
        if depth > 45 { return }
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""
        
        if role == "AXTextArea" || role == "AXTextField" {
            list.append(element)
            return
        }
        
        var childrenRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        if let children = childrenRef as? [AXUIElement] {
            for child in children {
                collectInputs(from: child, list: &list, depth: depth + 1)
            }
        }
    }
    
    // MARK: - Main Check Loop & Typing Debouncing
    
    private func pollInput() {
        guard let element = getFocusedElement() else {
            if lastFocusedElement != nil {
                clearOverlay()
                InputCornerBadge.shared.hide()
                lastFocusedElement = nil
                lastKnownText = ""
            }
            return
        }
        
        guard let fieldRect = frameOf(element) else {
            InputCornerBadge.shared.hide()
            return
        }
        
        lastFocusedElement = element
        lastFieldRect = fieldRect
        
        guard let (currentText, globalOffset) = extractTextAndOffset(from: element) else {
            clearOverlay()
            InputCornerBadge.shared.hide()
            return
        }
        
        // If field is too short or empty, mark clean
        if currentText.trimmingCharacters(in: .whitespacesAndNewlines).count < 5 {
            if !lastKnownText.isEmpty {
                clearOverlay()
                InputCornerBadge.shared.update(fieldRect: fieldRect, state: .clean)
                lastKnownText = currentText
            }
            return
        }
        
        // If text changed, update badge to typing immediately and reset debounce timer
        if currentText != lastKnownText {
            lastKnownText = currentText
            InputCornerBadge.shared.update(fieldRect: fieldRect, state: .typing)
            
            debounceTask?.cancel()
            debounceTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 650_000_000)
                guard !Task.isCancelled else { return }
                guard let self else { return }
                self.debounceTask = nil
                await self.performCheck(element: element, text: currentText, globalOffset: globalOffset, fieldRect: fieldRect)
            }
        } else if currentText != lastCheckedText && debounceTask == nil && !isChecking {
            // Text is idle but hasn't been successfully checked yet
            debounceTask = Task { @MainActor [weak self] in
                guard let self else { return }
                self.debounceTask = nil
                await self.performCheck(element: element, text: currentText, globalOffset: globalOffset, fieldRect: fieldRect)
            }
        }
    }
    
    private func performCheck(element: AXUIElement, text: String, globalOffset: Int, fieldRect: CGRect) async {
        guard !isChecking else { return }
        if text == lastCheckedText { return }
        guard await GECSidecar.shared.isReady else {
            // Sidecar model is still warming up, will retry on next tick
            return
        }
        
        isChecking = true
        defer { isChecking = false }
        debugLog("[GrammarOverlay] User stopped typing. Sending to AI for check...")
        
        do {
            let sentences = text.components(separatedBy: .init(charactersIn: ".!?\n"))
            if let lastSentence = sentences.last(where: { $0.trimmingCharacters(in: .whitespaces).count > 5 }) {
                let trimmed = lastSentence.trimmingCharacters(in: .whitespaces)
                let corrected = try await GECSidecar.shared.correct(text: trimmed, instruction: "")
                
                if corrected.trimmingCharacters(in: .whitespacesAndNewlines) != trimmed {
                    lastCheckedText = text
                    if let sentenceRange = text.range(of: trimmed) {
                        let nsSentenceRange = NSRange(sentenceRange, in: text)
                        let sentenceGlobalOffset = globalOffset + nsSentenceRange.location
                        let wordDifferences = alignTokens(original: trimmed, corrected: corrected)
                        
                        // Get sentence start/end bounds for click-based selection fallback
                        let sentenceStartBounds = getBoundsForRange(element: element, location: sentenceGlobalOffset, length: 1) ?? .zero
                        let sentenceEndBounds = getBoundsForRange(element: element, location: sentenceGlobalOffset + trimmed.utf16.count - 1, length: 1) ?? .zero
                        
                        var newSquiggles: [SquiggleData] = []
                        let primaryScreenHeight = CGDisplayBounds(CGMainDisplayID()).height
                        
                        // 1. Build issues for the corner badge card
                        var issues: [CorrectionIssue] = []
                        for diff in wordDifferences {
                            let wordGlobalOffset = sentenceGlobalOffset + diff.range.location
                            let wordStartBounds = getBoundsForRange(element: element, location: wordGlobalOffset, length: 1) ?? .zero
                            let wordEndBounds = diff.range.length > 0 ? (getBoundsForRange(element: element, location: wordGlobalOffset + diff.range.length - 1, length: 1) ?? wordStartBounds) : wordStartBounds
                            
                            let issue = CorrectionIssue(
                                original: diff.original,
                                corrected: diff.corrected,
                                explanation: diff.explanation,
                                onApply: { [weak self] in
                                    self?.applySentenceFix(
                                        element: element,
                                        offset: wordGlobalOffset,
                                        original: diff.original,
                                        corrected: diff.corrected,
                                        startBounds: wordStartBounds,
                                        endBounds: wordEndBounds
                                    )
                                }
                            )
                            issues.append(issue)
                        }
                        
                        // 2. Build full sentence correction for "Apply All"
                        let sentenceCorrection = CorrectionSentence(
                            original: trimmed,
                            corrected: corrected,
                            onApply: { [weak self] in
                                self?.applySentenceFix(
                                    element: element,
                                    offset: sentenceGlobalOffset,
                                    original: trimmed,
                                    corrected: corrected,
                                    startBounds: sentenceStartBounds,
                                    endBounds: sentenceEndBounds
                                )
                            }
                        )
                        
                        // 3. Try drawing inline squiggles for words that have valid coordinates
                        for diff in wordDifferences where diff.range.length > 0 {
                            let globalWordLocation = sentenceGlobalOffset + diff.range.location
                            guard let rect = getBoundsForRange(element: element, location: globalWordLocation, length: diff.range.length) else { continue }
                            
                            let wordStart = getBoundsForRange(element: element, location: globalWordLocation, length: 1) ?? rect
                            let wordEnd = getBoundsForRange(element: element, location: globalWordLocation + diff.range.length - 1, length: 1) ?? rect
                            
                            // Convert AX top-left coords to AppKit bottom-left coords
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
                            
                            let data = SquiggleData(
                                screenRect: windowFrame,
                                originalSentence: diff.original,
                                correctedSentence: diff.corrected,
                                sentenceGlobalOffset: globalWordLocation,
                                element: element,
                                window: window,
                                sentenceStartBounds: wordStart,
                                sentenceEndBounds: wordEnd
                            )
                            newSquiggles.append(data)
                        }
                        
                        self.clearOverlay()
                        self.activeSquiggles = newSquiggles
                        
                        // 4. Update the corner badge with mistake count, issues, and sentence correction
                        InputCornerBadge.shared.update(
                            fieldRect: fieldRect,
                            state: .errors(count: wordDifferences.count, issues: issues, sentenceCorrection: sentenceCorrection)
                        )
                    }
                } else {
                    lastCheckedText = text
                    self.clearOverlay()
                    InputCornerBadge.shared.update(fieldRect: fieldRect, state: .clean)
                }
            } else {
                lastCheckedText = text
                self.clearOverlay()
                InputCornerBadge.shared.update(fieldRect: fieldRect, state: .clean)
            }
        } catch {
            debugLog("[GrammarOverlayManager] AI check failed: \(error)")
            lastCheckedText = "" // Don't poison lastCheckedText so it retries on the next tick
        }
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
    
    private func clearOverlay() {
        for data in activeSquiggles {
            data.window.orderOut(nil)
        }
        activeSquiggles.removeAll()
    }
}

// MARK: - SwiftUI Views

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
                Text("Apply Fix")
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
        .onHover { _ in }
    }
}
