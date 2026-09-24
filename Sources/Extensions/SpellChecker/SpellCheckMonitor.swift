import Foundation
import AppKit
import ApplicationServices
import ClipboardManager

/// Represents a single misspelled word with its location and suggestions.
struct MisspelledWord {
    let word: String
    let range: NSRange           // Character range in the full text
    let screenBounds: CGRect     // Screen coordinates (top-left origin)
    let suggestions: [String]    // Correction suggestions from NSSpellChecker
}

/// Monitors the focused text element for changes and runs spell checking.
/// Uses macOS Accessibility API to read text and get word positions.
@MainActor
final class SpellCheckMonitor {
    static let shared = SpellCheckMonitor()

    private var isRunning = false
    private var debounceTimer: Timer?
    private var appObserver: Any?
    private var mouseMonitor: Any?
    private var axObserver: AXObserver?
    private var trackedElement: AXUIElement?
    private var trackedPid: pid_t = 0
    private var focusTimer: Timer?
    private let spellDocumentTag = NSSpellChecker.uniqueSpellDocumentTag()
    private let maximumCheckedCharacters = 1_024
    private let maximumIssuesPerPass = 8
    private var requestGeneration = 0

    /// Currently detected misspelled words
    private(set) var misspelledWords: [MisspelledWord] = []

    /// Words the user chose to ignore
    private var ignoredWords: Set<String> = []

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        print("[SpellChecker] Starting monitor")

        // Watch for app switches
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                Task { @MainActor in
                    self.attachToApp(pid: app.processIdentifier)
                }
            }
        }

        // Start global mouse move monitor for hover detection
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            guard let self else { return }
            Task { @MainActor in
                self.handleMouseMove(at: NSEvent.mouseLocation)
            }
        }

        // Attach to the current frontmost app
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            attachToApp(pid: frontApp.processIdentifier)
        }

        // AX value-change notifications belong to an individual element. Poll
        // focus cheaply so editors that move focus within the same app are
        // reattached instead of silently retaining the old field.
        focusTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let app = NSWorkspace.shared.frontmostApplication else { return }
            Task { @MainActor in
                self.attachToApp(pid: app.processIdentifier)
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        print("[SpellChecker] Stopping monitor")

        if let obs = appObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            appObserver = nil
        }

        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        focusTimer?.invalidate()
        focusTimer = nil

        detachObserver()
        misspelledWords = []
        SpellCheckOverlay.shared.clearAll()
    }

    // MARK: - App Tracking

    private func attachToApp(pid: pid_t) {
        // Skip our own app
        if let bundleId = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
           bundleId == "com.mactoys.inputmethod.MacToys" || isTerminal(bundleId) {
            detachObserver()
            SpellCheckOverlay.shared.clearAll()
            return
        }

        let appElement = AXUIElementCreateApplication(pid)

        // Crucial for Chromium / Electron / WebView2 apps (Slack, Teams, Chrome, VS Code)
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)

        // Find focused element
        var focusedRef: CFTypeRef?
        var err = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        if err != .success || focusedRef == nil {
            let systemWide = AXUIElementCreateSystemWide()
            err = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        }

        guard err == .success, let focused = focusedRef else {
            return
        }

        var element = focused as! AXUIElement

        // Resolve WebArea to actual inner text element in Chromium/Electron
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""
        if role == "AXWebArea" {
            if let resolved = resolveWebArea(element) {
                element = resolved
            }
        }

        if pid == trackedPid, let trackedElement, CFEqual(trackedElement, element) {
            return
        }

        detachObserver()
        trackedPid = pid

        var updatedRoleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &updatedRoleRef)
        let updatedRole = updatedRoleRef as? String ?? ""

        let textRoles = ["AXTextArea", "AXTextField", "AXStaticText", "AXComboBox", "AXWebArea"]
        guard textRoles.contains(updatedRole) || hasTextValue(element) else {
            misspelledWords = []
            SpellCheckOverlay.shared.clearAll()
            return
        }

        trackedElement = element

        // Create AX observer for value changes and selection changes (Chromium fires selection changes on typing)
        var observer: AXObserver?
        let result = AXObserverCreate(pid, { (observer, element, notification, refcon) in
            guard let refcon else { return }
            let monitor = Unmanaged<SpellCheckMonitor>.fromOpaque(refcon).takeUnretainedValue()
            DispatchQueue.main.async {
                monitor.scheduleSpellCheck()
            }
        }, &observer)

        if result == .success, let observer = observer {
            self.axObserver = observer
            AXObserverAddNotification(observer, element, kAXValueChangedNotification as CFString,
                                      Unmanaged.passUnretained(self).toOpaque())
            AXObserverAddNotification(observer, element, kAXSelectedTextChangedNotification as CFString,
                                      Unmanaged.passUnretained(self).toOpaque())
            CFRunLoopAddSource(CFRunLoopGetMain(),
                               AXObserverGetRunLoopSource(observer),
                               .defaultMode)
            print("[SpellChecker] Attached AX observer to pid \(pid), role: \(updatedRole)")
        }

        // Do an initial spell check right away
        scheduleSpellCheck()
    }

    private func detachObserver() {
        if let observer = axObserver, let element = trackedElement {
            AXObserverRemoveNotification(observer, element, kAXValueChangedNotification as CFString)
            AXObserverRemoveNotification(observer, element, kAXSelectedTextChangedNotification as CFString)
            CFRunLoopRemoveSource(CFRunLoopGetMain(),
                                  AXObserverGetRunLoopSource(observer),
                                  .defaultMode)
        }
        axObserver = nil
        trackedElement = nil
        trackedPid = 0
    }

    // MARK: - Spell Checking

    private func scheduleSpellCheck() {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.performSpellCheck()
            }
        }
    }

    private func performSpellCheck() {
        guard let element = trackedElement else { return }

        // Read text: try kAXValueAttribute, but if empty/nil/placeholder, use chunk-based extraction around caret
        guard let (text, globalOffset) = extractTextAndOffset(from: element), !text.isEmpty else {
            misspelledWords = []
            SpellCheckOverlay.shared.clearAll()
            return
        }

        let window = checkedWindow(in: text, element: element)
        let checkedText = window.text
        guard !checkedText.isEmpty else { return }

        // Spell checking is a background request. The completion arrives on an
        // arbitrary queue, so it must be discarded if the user continued typing
        // or changed focus before it completes.
        let checker = NSSpellChecker.shared
        let nsText = checkedText as NSString
        requestGeneration += 1
        let generation = requestGeneration
        checker.requestChecking(
            of: checkedText,
            range: NSRange(location: 0, length: nsText.length),
            types: NSTextCheckingTypes(NSTextCheckingResult.CheckingType.spelling.rawValue),
            options: nil,
            inSpellDocumentWithTag: spellDocumentTag
        ) { @Sendable [weak self] _, results, _, _ in
            let spellingRanges = results.filter { $0.resultType == .spelling }.map { $0.range }
            let safeBaseOffset = globalOffset + window.baseOffset
            
            Task { @MainActor [weak self] in
                guard let self,
                      self.requestGeneration == generation,
                      let currentElement = self.trackedElement else { return }
                self.apply(ranges: spellingRanges, text: checkedText, baseOffset: safeBaseOffset, element: currentElement)
            }
        }
    }

    private func apply(ranges: [NSRange], text: String, baseOffset: Int, element: AXUIElement) {
        let checker = NSSpellChecker.shared
        let nsText = text as NSString
        var found: [MisspelledWord] = []

        for range in ranges {
            guard found.count < maximumIssuesPerPass else { break }
            guard range.location != NSNotFound else { continue }
            let word = nsText.substring(with: range)
            guard word.count > 1, !ignoredWords.contains(word.lowercased()) else { continue }
            let elementRange = NSRange(location: baseOffset + range.location, length: range.length)
            guard let bounds = boundsForRange(element: element, range: elementRange) else { continue }

            let suggestions = checker.guesses(
                forWordRange: range,
                in: text,
                language: "en_US",
                inSpellDocumentWithTag: spellDocumentTag
            ) ?? []
            found.append(MisspelledWord(
                word: word,
                range: elementRange,
                screenBounds: bounds,
                suggestions: Array(suggestions.prefix(5))
            ))
        }
        misspelledWords = found
        SpellCheckOverlay.shared.update(words: found, element: element)
    }

    // MARK: - Coordinate Mapping

    private func boundsForRange(element: AXUIElement, range: NSRange) -> CGRect? {
        // Create AXValue for the range
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else { return nil }

        var boundsRef: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsRef
        )

        guard result == .success, let boundsValue = boundsRef else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect) else { return nil }
        guard rect.width > 1 && rect.height > 1 else { return nil }

        return rect
    }

    private func hasTextValue(_ element: AXUIElement) -> Bool {
        var valueRef: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success
            && valueRef is String
    }

    private func checkedWindow(in text: String, element: AXUIElement) -> (text: String, baseOffset: Int) {
        let nsText = text as NSString
        guard nsText.length > maximumCheckedCharacters else { return (text, 0) }

        var selectedRangeRef: CFTypeRef?
        var caretOffset = nsText.length
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeRef) == .success,
           let selectedRangeRef,
           CFGetTypeID(selectedRangeRef) == AXValueGetTypeID() {
            var selectedRange = CFRange()
            if AXValueGetValue(selectedRangeRef as! AXValue, .cfRange, &selectedRange) {
                caretOffset = min(max(0, selectedRange.location), nsText.length)
            }
        }
        var start = max(0, caretOffset - maximumCheckedCharacters / 2)
        var end = min(nsText.length, start + maximumCheckedCharacters)
        start = max(0, end - maximumCheckedCharacters)

        // Avoid checking a slice that starts halfway through a word.
        while start > 0, CharacterSet.alphanumerics.contains(UnicodeScalar(nsText.character(at: start))!) {
            start -= 1
        }
        while end < nsText.length, CharacterSet.alphanumerics.contains(UnicodeScalar(nsText.character(at: end - 1))!) {
            end += 1
        }
        return (nsText.substring(with: NSRange(location: start, length: end - start)), start)
    }

    private func isTerminal(_ bundleIdentifier: String) -> Bool {
        ["com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty", "net.kovidgoyal.kitty"].contains(bundleIdentifier)
    }

    // MARK: - Mouse Hover

    private func handleMouseMove(at screenPoint: NSPoint) {
        guard !misspelledWords.isEmpty else {
            CorrectionPopup.shared.hide()
            return
        }

        // Convert from AppKit coordinates (bottom-left) to screen coordinates (top-left)
        // AX API returns top-left origin coordinates
        let desktopTop = NSScreen.screens.map(\.frame.maxY).max() ?? 0

        for word in misspelledWords {
            // AX bounds are in screen coords (top-left origin)
            // NSEvent.mouseLocation is in AppKit coords (bottom-left origin)
            let flippedY = desktopTop - word.screenBounds.origin.y - word.screenBounds.height
            let appKitRect = CGRect(
                x: word.screenBounds.origin.x,
                y: flippedY,
                width: word.screenBounds.width,
                height: word.screenBounds.height
            )

            // Expand hit area slightly for easier targeting
            let expandedRect = appKitRect.insetBy(dx: -4, dy: -4)

            if expandedRect.contains(screenPoint) {
                CorrectionPopup.shared.show(
                    for: word,
                    at: appKitRect,
                    onAccept: { [weak self] replacement in
                        self?.replaceWord(word, with: replacement)
                    },
                    onDismiss: { [weak self] in
                        self?.ignoreWord(word.word)
                    }
                )
                return
            }
        }

        // Mouse is not over any misspelled word
        CorrectionPopup.shared.hideIfNotHovered()
    }

    // MARK: - Actions

    func replaceWord(_ word: MisspelledWord, with replacement: String) {
        guard let element = trackedElement else { return }

        CorrectionPopup.shared.hide()

        // 1. Get the target application PID from AXUIElement
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let targetApp = NSRunningApplication(processIdentifier: pid)

        // 2. Select the misspelled word range via AX
        var cfRange = CFRange(location: word.range.location, length: word.range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else { return }
        AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue)

        // 3. Re-activate the target app so it receives key events
        if let app = targetApp {
            if #available(macOS 14.0, *) {
                NSApp.yieldActivation(to: app)
            }
            app.activate(options: .activateIgnoringOtherApps)
        }

        // 4. Paste the replacement via Cmd+V (required for React / Quill / Teams / Slack)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.pasteText(replacement)

            print("[SpellChecker] Replaced '\(word.word)' with '\(replacement)' via Cmd+V")

            // Re-check after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self?.performSpellCheck()
            }
        }
    }

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

        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
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
    }

    func ignoreWord(_ word: String) {
        ignoredWords.insert(word.lowercased())
        CorrectionPopup.shared.hide()
        // Re-check to remove the underline
        performSpellCheck()
    }

    // MARK: - Chromium & WebArea Support

    private func resolveWebArea(_ webArea: AXUIElement) -> AXUIElement? {
        // Fast path: direct focused child query on AXWebArea
        var innerFocusedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(webArea, kAXFocusedUIElementAttribute as CFString, &innerFocusedRef) == .success,
           let inner = innerFocusedRef as! AXUIElement? {
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(inner, kAXRoleAttribute as CFString, &roleRef)
            let role = roleRef as? String ?? ""
            if role == "AXTextArea" || role == "AXTextField" {
                return inner
            }
        }

        // Recursive fallback
        var allInputs: [AXUIElement] = []
        collectInputs(from: webArea, list: &allInputs, depth: 0)

        for inp in allInputs {
            var isFocRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(inp, kAXFocusedAttribute as CFString, &isFocRef) == .success,
               let isFoc = isFocRef as? Bool, isFoc {
                return inp
            }
        }

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

    private func extractTextAndOffset(from element: AXUIElement) -> (String, Int)? {
        // Strategy 1: Standard kAXValueAttribute
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
           let val = valueRef {
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
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let rangeVal = rangeRef {
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
}
