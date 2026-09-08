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

        detachObserver()
        misspelledWords = []
        SpellCheckOverlay.shared.clearAll()
    }

    // MARK: - App Tracking

    private func attachToApp(pid: pid_t) {
        // Don't re-attach to the same app
        guard pid != trackedPid else {
            // Still refresh text on app re-focus
            scheduleSpellCheck()
            return
        }

        detachObserver()
        trackedPid = pid

        // Skip our own app
        if let bundleId = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
           bundleId == "com.mactoys.app" {
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
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.performSpellCheck()
            }
        }
    }

    private func performSpellCheck() {
        guard let element = trackedElement else { return }

        // Read the full text
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let text = valueRef as? String, !text.isEmpty else {
            misspelledWords = []
            SpellCheckOverlay.shared.clearAll()
            return
        }

        print("[SpellChecker] Checking text (\(text.count) chars)")

        // Run NSSpellChecker over the full text
        let checker = NSSpellChecker.shared
        var offset = 0
        var found: [MisspelledWord] = []

        while offset < text.count {
            let misspelledRange = checker.checkSpelling(
                of: text,
                startingAt: offset,
                language: "en",
                wrap: false,
                inSpellDocumentWithTag: 0,
                wordCount: nil
            )

            guard misspelledRange.location != NSNotFound else { break }

            let nsText = text as NSString
            let word = nsText.substring(with: misspelledRange)

            // Skip ignored words
            if ignoredWords.contains(word.lowercased()) {
                offset = misspelledRange.location + misspelledRange.length
                continue
            }

            // Skip very short words (1-2 chars) to avoid noise
            if word.count <= 1 {
                offset = misspelledRange.location + misspelledRange.length
                continue
            }

            // Get suggestions
            let suggestions = checker.guesses(
                forWordRange: misspelledRange,
                in: text,
                language: "en",
                inSpellDocumentWithTag: 0
            ) ?? []

            // Get screen bounds for this word range using AX API
            if let bounds = boundsForRange(element: element, range: misspelledRange) {
                found.append(MisspelledWord(
                    word: word,
                    range: misspelledRange,
                    screenBounds: bounds,
                    suggestions: Array(suggestions.prefix(5))
                ))
            }

            offset = misspelledRange.location + misspelledRange.length
        }

        misspelledWords = found
        print("[SpellChecker] Found \(found.count) misspelled words")

        // Update overlay
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

    // MARK: - Mouse Hover

    private func handleMouseMove(at screenPoint: NSPoint) {
        guard !misspelledWords.isEmpty else {
            CorrectionPopup.shared.hide()
            return
        }

        // Convert from AppKit coordinates (bottom-left) to screen coordinates (top-left)
        // AX API returns top-left origin coordinates
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0

        for word in misspelledWords {
            // AX bounds are in screen coords (top-left origin)
            // NSEvent.mouseLocation is in AppKit coords (bottom-left origin)
            let flippedY = screenHeight - word.screenBounds.origin.y - word.screenBounds.height
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
