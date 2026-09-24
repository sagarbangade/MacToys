import Foundation
import AppKit
import SwiftUI

// Custom HostingView that accepts clicks immediately (no double-click needed on non-activating panel)
private class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

/// A small floating popup that appears when hovering over a misspelled word,
/// showing the correction and accept/dismiss actions. Styled like Grammarly.
@MainActor
final class CorrectionPopup {
    static let shared = CorrectionPopup()

    private var panel: NSPanel?
    private var isMouseInsidePopup = false
    private var hideTimer: Timer?
    private var currentWord: MisspelledWord?
    private var onAcceptAction: ((String) -> Void)?
    private var onDismissAction: (() -> Void)?

    private init() {
        setupPanel()
    }

    private func setupPanel() {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .popUpMenu
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.ignoresMouseEvents = false
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.animationBehavior = .utilityWindow

        self.panel = p
    }

    func show(for word: MisspelledWord, at wordRect: CGRect,
              onAccept: @escaping (String) -> Void,
              onDismiss: @escaping () -> Void) {
        // Don't re-show for the same word
        if currentWord?.word == word.word && currentWord?.range == word.range && panel?.isVisible == true {
            hideTimer?.invalidate()
            hideTimer = nil
            return
        }

        currentWord = word
        onAcceptAction = onAccept
        onDismissAction = onDismiss

        guard let panel = panel else { return }

        let topSuggestion = word.suggestions.first ?? word.word

        // Build the popup content
        let hostingView = ClickThroughHostingView(rootView: CorrectionPopupView(
            originalWord: word.word,
            suggestion: topSuggestion,
            allSuggestions: word.suggestions,
            onAccept: { [weak self] replacement in
                self?.onAcceptAction?(replacement)
            },
            onDismiss: { [weak self] in
                self?.onDismissAction?()
            }
        ))

        panel.contentView = hostingView

        // Force layout to get accurate size
        hostingView.layout()
        let size = hostingView.fittingSize
        let safeWidth = max(size.width, 180)
        let safeHeight = max(size.height, 60)

        // Position above the word
        let x = wordRect.origin.x
        let y = wordRect.maxY + 6

        panel.setFrame(NSRect(x: x, y: y, width: safeWidth, height: safeHeight), display: true)
        panel.orderFrontRegardless()

        // Track mouse entering/leaving the popup
        hideTimer?.invalidate()
        hideTimer = nil
    }

    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        panel?.orderOut(nil)
        currentWord = nil
    }

    func hideIfNotHovered() {
        // Give user a moment to move mouse to the popup
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                // Check if mouse is inside the popup
                guard let panel = self.panel, panel.isVisible else { return }
                let mouseLocation = NSEvent.mouseLocation
                let popupFrame = panel.frame
                let expandedFrame = popupFrame.insetBy(dx: -10, dy: -10)
                if !expandedFrame.contains(mouseLocation) {
                    self.hide()
                }
            }
        }
    }
}

// MARK: - SwiftUI Popup View

struct CorrectionPopupView: View {
    let originalWord: String
    let suggestion: String
    let allSuggestions: [String]
    let onAccept: (String) -> Void
    let onDismiss: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            Text("Correct your spelling")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            // Main suggestion - clickable
            Button(action: { onAccept(suggestion) }) {
                Text(suggestion)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
            .onHover { hovering in isHovered = hovering }

            // Additional suggestions if available
            if allSuggestions.count > 1 {
                HStack(spacing: 6) {
                    ForEach(allSuggestions.dropFirst().prefix(3), id: \.self) { alt in
                        Button(action: { onAccept(alt) }) {
                            Text(alt)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.blue.opacity(0.7))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.08))
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            // Dismiss action
            Button(action: { onDismiss() }) {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                    Text("Dismiss")
                        .font(.system(size: 11))
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThickMaterial)
                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
}
