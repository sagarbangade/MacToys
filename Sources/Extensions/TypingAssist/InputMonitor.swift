import Foundation
import CoreGraphics
import AppKit

/// Monitors system-wide keystrokes via CGEvent tap.
/// The C callback fires on the main RunLoop, so state access is thread-safe.
public final class InputMonitor: @unchecked Sendable {
    public static let shared = InputMonitor()

    nonisolated(unsafe) var eventPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // State accessed from the C callback (always on main thread via main RunLoop)
    nonisolated(unsafe) private var currentWord: String = ""
    nonisolated(unsafe) private var activeSuggestions: [String] = []
    nonisolated(unsafe) private var selectedSuggestionIndex = 0
    nonisolated(unsafe) private var isCompletingPartialWord = false
    nonisolated(unsafe) private var compositionGeneration = 0
    nonisolated(unsafe) private var isOutOfSync = false

    fileprivate let syntheticEventMarker: Int64 = 0x4D54_4153

    private init() {}

    // MARK: - Lifecycle

    public func start() {
        if eventPort != nil {
            print("[TypingAssist] Event tap already running, skipping")
            return
        }

        let eventMask: CGEventMask = 1 << CGEventType.keyDown.rawValue

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("[TypingAssist] ❌ CGEvent.tapCreate failed! Accessibility permission is NOT granted.")
            print("[TypingAssist] 💡 Go to System Settings → Privacy & Security → Accessibility → Enable MacToys")
            return
        }

        self.eventPort = port
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        print("[TypingAssist] Event tap started successfully")
    }

    public func stop() {
        if let port = eventPort {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
            self.eventPort = nil
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            self.runLoopSource = nil
        }
        clearSuggestions()
        print("[TypingAssist] Event tap stopped")
    }

    // MARK: - Event Handling

    fileprivate func handleKeyDown(event: CGEvent) -> Unmanaged<CGEvent>? {
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)

        // ── Tab (48): accept candidate ──
        if keycode == 48, let suggestion = selectedSuggestion {
            accept(suggestion)
            return nil // swallow the Tab
        }

        // ── Left/right: choose candidate ──
        if (keycode == 123 || keycode == 124 || keycode == 125 || keycode == 126) {
            if !activeSuggestions.isEmpty {
                if keycode == 123 || keycode == 124 {
                    let delta = keycode == 123 ? -1 : 1
                    selectedSuggestionIndex = (selectedSuggestionIndex + delta + activeSuggestions.count) % activeSuggestions.count
                    updateSuggestionUI()
                    return nil
                }
            } else {
                isOutOfSync = true
                currentWord = ""
                clearSuggestions()
            }
        }

        // ── Escape (53): dismiss ──
        if keycode == 53, !activeSuggestions.isEmpty {
            clearSuggestions()
            return nil
        }

        // ── Backspace (51) ──
        if keycode == 51 {
            // The generated suffix is selected in the focused editor. Let the
            // app delete that selection, leaving the user's typed prefix intact.
            if isCompletingPartialWord, selectedSuggestion != nil {
                clearSuggestions()
                return Unmanaged.passUnretained(event)
            }
            if currentWord.isEmpty {
                isOutOfSync = true
                clearSuggestions()
                return Unmanaged.passUnretained(event)
            }
            currentWord.removeLast()
            if isOutOfSync {
                clearSuggestions()
            } else {
                showSuggestions(forPartialWord: currentWord)
            }
            return Unmanaged.passUnretained(event)
        }

        // We only care about characters if no modifiers (other than Shift) are held
        let flags = event.flags
        let ignoredFlags: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate]
        guard flags.intersection(ignoredFlags).isEmpty else {
            return Unmanaged.passUnretained(event)
        }

        var unichar = UniChar()
        var actualLength = 0
        event.keyboardGetUnicodeString(maxStringLength: 1, actualStringLength: &actualLength, unicodeString: &unichar)
        guard actualLength > 0, let char = String(utf16CodeUnits: &unichar, count: 1).first else {
            return Unmanaged.passUnretained(event)
        }

        if char == " " || char == "\n" || char == "\r" {
            // Space commits an inline completion by collapsing the selected
            // suffix, then the original Space event creates the word boundary.
            if isCompletingPartialWord, let suggestion = selectedSuggestion {
                currentWord = suggestion
                clearSuggestions()
                collapseSelectionToEnd()
            }

            // ── Word boundary: predict next word ──
            let finishedWord = currentWord
            currentWord = ""
            isOutOfSync = false

            if !finishedWord.isEmpty {
                print("[TypingAssist] Word completed: \"\(finishedWord)\" — looking up prediction...")
                let generation = self.compositionGeneration
                DispatchQueue.main.async {
                    guard self.compositionGeneration == generation else { return }
                    PredictionEngine.shared.recordWord(finishedWord)
                    self.showSuggestions(after: finishedWord)
                }
            }
        } else if char.isLetter || char.isNumber || char == "'" || char == "-" {
            if isOutOfSync {
                return Unmanaged.passUnretained(event)
            }
            currentWord.append(char)
            showSuggestions(forPartialWord: currentWord)
        } else {
            // Punctuation — reset
            currentWord = ""
            isOutOfSync = false
            clearSuggestions()
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Text Injection

    private var selectedSuggestion: String? {
        activeSuggestions.indices.contains(selectedSuggestionIndex) ? activeSuggestions[selectedSuggestionIndex] : nil
    }

    private func showSuggestions(forPartialWord word: String) {
        guard !word.isEmpty else {
            clearSuggestions()
            return
        }
        let generation = self.compositionGeneration
        DispatchQueue.main.async {
            guard self.compositionGeneration == generation else { return }
            let candidates = PredictionEngine.shared.suggestions(after: nil, partialWord: word)
            self.present(candidates, completesPartialWord: true)
        }
    }

    private func showSuggestions(after word: String) {
        let generation = self.compositionGeneration
        DispatchQueue.main.async {
            guard self.compositionGeneration == generation else { return }
            let candidates = PredictionEngine.shared.suggestions(after: word, partialWord: "")
            self.present(candidates, completesPartialWord: false)
        }
    }

    private func present(_ candidates: [String], completesPartialWord: Bool) {
        activeSuggestions = completesPartialWord
            ? candidates.filter { $0.caseInsensitiveCompare(currentWord) != .orderedSame }
            : candidates
        selectedSuggestionIndex = 0
        isCompletingPartialWord = completesPartialWord
        if completesPartialWord {
            composeSelectedPartialWord()
        } else {
            updateSuggestionUI()
        }
    }

    private func updateSuggestionUI() {
        guard !activeSuggestions.isEmpty else {
            DispatchQueue.main.async { SuggestionUI.shared.hide() }
            return
        }
        let generation = self.compositionGeneration
        DispatchQueue.main.async {
            guard self.compositionGeneration == generation else { return }
            SuggestionUI.shared.show(
                suggestions: self.activeSuggestions,
                selectedIndex: self.selectedSuggestionIndex,
                at: CaretTracker.shared.getSuggestionAnchor()
            )
        }
    }

    private func clearSuggestions() {
        compositionGeneration += 1
        activeSuggestions = []
        selectedSuggestionIndex = 0
        isCompletingPartialWord = false
        DispatchQueue.main.async { SuggestionUI.shared.hide() }
    }

    private func accept(_ suggestion: String) {
        let completesPartialWord = isCompletingPartialWord
        let text: String
        if completesPartialWord {
            // The selected suffix is already in the editor. Tab only commits it.
            text = ""
            currentWord = suggestion
            collapseSelectionToEnd()
        } else {
            text = suggestion + " "
            currentWord = ""
        }
        clearSuggestions()
        injectText(text)

        // Accepted next-word candidates need to participate in learning and
        // immediately produce the following candidate ("how" -> "are" -> "you").
        guard !completesPartialWord else { return }
        DispatchQueue.main.async {
            PredictionEngine.shared.recordWord(suggestion)
            self.showSuggestions(after: suggestion)
        }
    }

    private func injectText(_ text: String) {
        guard !text.isEmpty else { return }
        DispatchQueue.main.async {
            self.typeText(text)
        }
    }

    /// Writes only the missing suffix and selects it, producing native inline
    /// composition in the target field instead of an approximation in an overlay.
    private func composeSelectedPartialWord() {
        guard let suggestion = selectedSuggestion,
              suggestion.hasPrefix(currentWord),
              suggestion != currentWord else {
            updateSuggestionUI()
            return
        }
        let suffix = String(suggestion.dropFirst(currentWord.count))
        let generation = compositionGeneration + 1
        compositionGeneration = generation

        DispatchQueue.main.async {
            guard self.compositionGeneration == generation else { return }
            self.pasteText(suffix) {
                guard self.compositionGeneration == generation else { return }
                self.selectLastCharacters(suffix.count)
                self.updateSuggestionUI()
            }
        }
    }

    private func pasteText(_ text: String, completion: @escaping @Sendable () -> Void) {
        self.typeText(text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: completion)
    }

    private func typeText(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        let utf16Chars = Array(text.utf16)
        
        for char in utf16Chars {
            var unit = char
            if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
               let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)
                up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)
                
                down.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
                up.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
                
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
            }
        }
    }

    private func selectLastCharacters(_ count: Int) {
        postKey(123, flags: .maskShift, count: count)
    }

    private func collapseSelectionToEnd() {
        postKey(124, flags: [], count: 1)
    }

    private func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags, count: Int) {
        let source = CGEventSource(stateID: .hidSystemState)
        for _ in 0..<count {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { continue }
            down.flags = flags
            up.flags = flags
            down.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
            up.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }
}

// MARK: - C Function Pointer (no captures allowed)

/// Top-level C callback for the CGEvent tap. Extracts the InputMonitor from refcon.
private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon = refcon else {
        return Unmanaged.passUnretained(event)
    }
    let monitor = Unmanaged<InputMonitor>.fromOpaque(refcon).takeUnretainedValue()

    // Ignore keystrokes that this module posts to paste/select a completion.
    if event.getIntegerValueField(.eventSourceUserData) == monitor.syntheticEventMarker {
        return Unmanaged.passUnretained(event)
    }

    // Re-enable if the system disabled our tap (happens if callback is too slow)
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let port = monitor.eventPort {
            CGEvent.tapEnable(tap: port, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    guard type == .keyDown else {
        return Unmanaged.passUnretained(event)
    }

    return monitor.handleKeyDown(event: event)
}
