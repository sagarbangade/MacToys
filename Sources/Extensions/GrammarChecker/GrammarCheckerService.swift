import Foundation
import Cocoa
import ApplicationServices
import ClipboardManager

@MainActor
public final class GrammarCheckerService {
    public static let shared = GrammarCheckerService()
    
    private var previousApp: NSRunningApplication?

    private init() {}

    public private(set) var currentOriginalText: String? = nil
    
    public func execute() {
        previousApp = NSWorkspace.shared.frontmostApplication
        
        getSelectedText { selectedText in
            DispatchQueue.main.async {
                if let text = selectedText {
                    print("[GrammarChecker] Extracted text: \(text)")
                    self.currentOriginalText = text
                    GrammarCheckerUI.shared.show(originalText: text)
                } else {
                    print("[GrammarChecker] Failed to extract text.")
                    NSSound.beep()
                }
            }
        }
    }
    
    public func cancel() {
        if let text = currentOriginalText {
            replaceSelectedText(with: text)
        }
        currentOriginalText = nil
    }
    
    public func replaceSelectedText(with newText: String) {
        currentOriginalText = nil
        GrammarCheckerUI.shared.hide()
        NSApp.hide(nil)
        
        if let app = previousApp {
            if #available(macOS 14.0, *) {
                NSApp.yieldActivation(to: app)
            }
            app.activate(options: .activateIgnoringOtherApps)
        }
        
        // Wait for focus to restore before typing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.pasteText(newText)
        }
    }

    private func getSelectedText(completion: @escaping @Sendable (String?) -> Void) {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElementRef: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElementRef)
        
        var axText: String?
        if error == .success, let focusedElement = focusedElementRef {
            let element = focusedElement as! AXUIElement
            var selectedTextRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextRef) == .success {
                if let text = selectedTextRef as? String, !text.isEmpty {
                    axText = text
                }
            }
        }
        
        let fallbackText = axText
        
        ClipboardWatcher.isPaused = true
        
        // Use Cmd+X (Cut) instead of Cmd+C!
        // This solves the problem where apps lose text selection when the popup opens.
        // By cutting it immediately, we remove the text while it's still selected.
        // We will just paste the new text at the cursor when they hit Replace.
        let pasteboard = NSPasteboard.general
        let oldString = pasteboard.string(forType: .string)
        
        pasteboard.clearContents()
        let initialChangeCount = pasteboard.changeCount
        
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents], state: .eventSuppressionStateSuppressionInterval)
        
        let vKeyCode_c: CGKeyCode = 8 // 'c'
        let cmdC_down = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode_c, keyDown: true)
        cmdC_down?.flags = .maskCommand
        let cmdC_up = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode_c, keyDown: false)
        cmdC_up?.flags = .maskCommand
        
        cmdC_down?.post(tap: .cgAnnotatedSessionEventTap)
        cmdC_up?.post(tap: .cgAnnotatedSessionEventTap)
        
        DispatchQueue.global().async {
            var newText: String? = nil
            let pb = NSPasteboard.general
            
            // Poll up to 10 times (500ms max)
            for _ in 0..<10 {
                Thread.sleep(forTimeInterval: 0.05)
                if pb.changeCount != initialChangeCount {
                    newText = pb.string(forType: .string)
                    break
                }
            }
            
            // Now that Cmd+C has finished (or timed out), we can safely restore the old clipboard
            if oldString != nil {
                pb.clearContents()
                pb.setString(oldString!, forType: .string)
            }
            
            // Simulate Backspace to delete the highlighted text since we used Cmd+C instead of Cmd+X
            let asyncSource = CGEventSource(stateID: .combinedSessionState)
            asyncSource?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents], state: .eventSuppressionStateSuppressionInterval)
            
            let vKeyCode_delete: CGKeyCode = 51 // 'delete'
            let delete_down = CGEvent(keyboardEventSource: asyncSource, virtualKey: vKeyCode_delete, keyDown: true)
            let delete_up = CGEvent(keyboardEventSource: asyncSource, virtualKey: vKeyCode_delete, keyDown: false)
            delete_down?.post(tap: .cgAnnotatedSessionEventTap)
            delete_up?.post(tap: .cgAnnotatedSessionEventTap)
            
            DispatchQueue.main.async {
                ClipboardWatcher.shared.syncChangeCount()
                ClipboardWatcher.isPaused = false
                
                let finalText = (newText != nil && !newText!.isEmpty) ? newText : fallbackText
                if let text = finalText, !text.isEmpty {
                    ClipboardWatcher.shared.ignore(text)
                    if let str = oldString {
                        ClipboardWatcher.shared.ignore(str)
                    }
                    completion(text)
                } else {
                    completion(nil)
                }
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
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
            let asyncSource = CGEventSource(stateID: .combinedSessionState)
            asyncSource?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents], state: .eventSuppressionStateSuppressionInterval)
            let pb = NSPasteboard.general
            if needsRestore {
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
}
