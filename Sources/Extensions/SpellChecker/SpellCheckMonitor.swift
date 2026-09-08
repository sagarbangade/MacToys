import Foundation
import AppKit
import ApplicationServices

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
           bundleId == "com.mactoys.app" || isTerminal(bundleId) {
            detachObserver()
            SpellCheckOverlay.shared.clearAll()
            return
        }

        let appElement = AXUIElementCreateApplication(pid)

        // Find focused element
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef else {
            print("[SpellChecker] No focused element for pid \(pid)")
            return
        }

        let element = focused as! AXUIElement

        if pid == trackedPid, let trackedElement, CFEqual(trackedElement, element) {
            return
        }

        detachObserver()
        trackedPid = pid

        // Check if the element has a text value (i.e., it's a text field/editor)
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""

        let textRoles = ["AXTextArea", "AXTextField", "AXStaticText", "AXComboBox", "AXWebArea"]
        guard textRoles.contains(role) || hasTextValue(element) else {
            print("[SpellChecker] Focused element role '\(role)' is not a text field")
            misspelledWords = []
            SpellCheckOverlay.shared.clearAll()
            return
        }

        trackedElement = element

        // Create AX observer for value changes
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
            CFRunLoopAddSource(CFRunLoopGetMain(),
                               AXObserverGetRunLoopSource(observer),
                               .defaultMode)
            print("[SpellChecker] Attached AX observer to pid \(pid), role: \(role)")
        }

        // Do an initial spell check right away
        scheduleSpellCheck()
    }

    private func detachObserver() {
        if let observer = axObserver, let element = trackedElement {
            AXObserverRemoveNotification(observer, element, kAXValueChangedNotification as CFString)
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

        // Read text around the caret, not an entire document or terminal buffer.
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let text = valueRef as? String, !text.isEmpty else {
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
            let safeBaseOffset = window.baseOffset
            
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

        // Use AX API to select the range and replace
        var cfRange = CFRange(location: word.range.location, length: word.range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else { return }

        // Set the selection to the misspelled word
        AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue)

        // Replace with the correction
        AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, replacement as CFString)

        print("[SpellChecker] Replaced '\(word.word)' with '\(replacement)'")

        // Re-check after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.performSpellCheck()
        }
    }

    func ignoreWord(_ word: String) {
        ignoredWords.insert(word.lowercased())
        CorrectionPopup.shared.hide()
        // Re-check to remove the underline
        performSpellCheck()
    }
}
