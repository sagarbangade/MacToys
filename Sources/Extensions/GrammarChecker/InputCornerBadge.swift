import Foundation
import AppKit
import SwiftUI

/// Represents a single detected issue for the corner badge card
public struct CorrectionIssue: Identifiable {
    public let id = UUID()
    public let original: String
    public let corrected: String
    public let explanation: String
    public let onApply: () -> Void
    
    public init(original: String, corrected: String, explanation: String, onApply: @escaping () -> Void) {
        self.original = original
        self.corrected = corrected
        self.explanation = explanation
        self.onApply = onApply
    }
}

/// Represents a full sentence correction for the "Apply All" action
public struct CorrectionSentence {
    public let original: String
    public let corrected: String
    public let onApply: () -> Void
    
    public init(original: String, corrected: String, onApply: @escaping () -> Void) {
        self.original = original
        self.corrected = corrected
        self.onApply = onApply
    }
}

public enum CornerBadgeState {
    case hidden
    case typing
    case clean
    case errors(count: Int, issues: [CorrectionIssue], sentenceCorrection: CorrectionSentence? = nil)
}

// Custom HostingView that accepts clicks immediately on non-activating panels
private class BadgeHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

/// Floating corner badge controller that anchors to the bottom-right of active input fields
@MainActor
public final class InputCornerBadge {
    public static let shared = InputCornerBadge()

    private var badgeWindow: NSPanel?
    private var popoverWindow: NSPanel?
    private var currentState: CornerBadgeState = .hidden
    private var currentFieldRect: CGRect = .zero
    private var isHovering = false
    private var hidePopoverTimer: Timer?

    private init() {
        setupBadgeWindow()
        setupPopoverWindow()
    }

    private func setupBadgeWindow() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 28, height: 28),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating + 1
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.animationBehavior = .utilityWindow

        self.badgeWindow = panel
    }

    private func setupPopoverWindow() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 270, height: 180),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu + 1
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow

        self.popoverWindow = panel
    }

    /// Update badge position and state based on the current element frame
    public func update(fieldRect: CGRect, state: CornerBadgeState) {
        self.currentState = state
        self.currentFieldRect = fieldRect

        guard let window = badgeWindow else { return }

        switch state {
        case .hidden:
            hide()
            return
        case .clean, .typing:
            popoverWindow?.orderOut(nil)
        default:
            break
        }

        // Calculate AppKit bottom-left coords from AX top-left coords
        let primaryScreenHeight = CGDisplayBounds(CGMainDisplayID()).height
        let badgeSize: CGFloat = 28
        let paddingX: CGFloat = 12
        let paddingY: CGFloat = 6

        // Position at bottom-right corner inside the input field with breathing room from action buttons
        let x = fieldRect.origin.x + fieldRect.width - badgeSize - paddingX
        let y = primaryScreenHeight - (fieldRect.origin.y + fieldRect.height) + paddingY

        // Ensure within screen
        let badgeFrame = NSRect(x: x, y: y, width: badgeSize, height: badgeSize)
        debugLog("[InputCornerBadge] update state=\(stateDescription(state)) frame=(\(Int(x)), \(Int(y)), \(Int(badgeSize)), \(Int(badgeSize)))")

        let rootView = CornerBadgeView(
            state: state,
            onHover: { [weak self] hovering in
                self?.handleHover(hovering)
            },
            onClick: { [weak self] in
                self?.togglePopover()
            }
        )

        window.contentView = BadgeHostingView(rootView: rootView)
        window.setFrame(badgeFrame, display: true)
        window.orderFrontRegardless()
    }

    private func stateDescription(_ state: CornerBadgeState) -> String {
        switch state {
        case .hidden: return "hidden"
        case .typing: return "typing"
        case .clean: return "clean"
        case .errors(let count, _, _): return "errors(\(count))"
        }
    }

    public func hide() {
        badgeWindow?.orderOut(nil)
        popoverWindow?.orderOut(nil)
        currentState = .hidden
    }

    private func handleHover(_ hovering: Bool) {
        isHovering = hovering
        if hovering {
            hidePopoverTimer?.invalidate()
            hidePopoverTimer = nil
            showPopover()
        } else {
            scheduleHidePopover()
        }
    }

    private func togglePopover() {
        if popoverWindow?.isVisible == true {
            popoverWindow?.orderOut(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard case .errors(_, let issues, let sentenceCorrection) = currentState, (!issues.isEmpty || sentenceCorrection != nil) else { return }
        guard let popover = popoverWindow, let badge = badgeWindow else { return }
        debugLog("[InputCornerBadge] showPopover: displaying \(issues.count) suggestions")

        let popoverView = CornerBadgePopoverView(
            issues: issues,
            sentenceCorrection: sentenceCorrection,
            onDismiss: { [weak self] in
                self?.popoverWindow?.orderOut(nil)
            }
        )

        let hostingView = BadgeHostingView(rootView: popoverView)
        popover.contentView = hostingView
        hostingView.layout()

        let size = hostingView.fittingSize
        let popoverWidth = max(size.width, 275)
        let popoverHeight = max(size.height, 90)

        // Anchor above the badge
        let badgeFrame = badge.frame
        let popX = badgeFrame.maxX - popoverWidth
        let popY = badgeFrame.maxY + 6

        popover.setFrame(NSRect(x: popX, y: popY, width: popoverWidth, height: popoverHeight), display: true)
        popover.orderFrontRegardless()
    }

    private func scheduleHidePopover() {
        hidePopoverTimer?.invalidate()
        hidePopoverTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                let mouseLocation = NSEvent.mouseLocation
                if let popover = self.popoverWindow, popover.isVisible {
                    if !popover.frame.insetBy(dx: -10, dy: -10).contains(mouseLocation) &&
                       !(self.badgeWindow?.frame.insetBy(dx: -10, dy: -10).contains(mouseLocation) ?? false) {
                        popover.orderOut(nil)
                    }
                }
            }
        }
    }
}

// MARK: - SwiftUI Corner Badge View (Apple Intelligence / Siri Aesthetic)

struct CornerBadgeView: View {
    let state: CornerBadgeState
    let onHover: (Bool) -> Void
    let onClick: () -> Void

    @State private var isHovered = false
    @State private var rotationAngle: Double = 0

    var body: some View {
        Button(action: onClick) {
            ZStack {
                switch state {
                case .hidden:
                    EmptyView()
                case .typing:
                    // Siri-Style Breathing Chromatic Ring with Frosted Glass Core
                    ZStack {
                        Circle()
                            .stroke(
                                AngularGradient(
                                    colors: [
                                        Color(red: 0.98, green: 0.22, blue: 0.48),
                                        Color(red: 0.65, green: 0.32, blue: 0.98),
                                        Color(red: 0.18, green: 0.65, blue: 0.98),
                                        Color(red: 0.98, green: 0.62, blue: 0.22),
                                        Color(red: 0.98, green: 0.22, blue: 0.48)
                                    ],
                                    center: .center
                                ),
                                lineWidth: 2.2
                            )
                            .rotationEffect(.degrees(rotationAngle))
                            .blur(radius: 0.4)
                        
                        Circle()
                            .fill(.ultraThinMaterial)
                            .padding(2)
                        
                        ProgressView()
                            .scaleEffect(0.5)
                    }
                    .onAppear {
                        withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                            rotationAngle = 360
                        }
                    }
                case .clean:
                    // Frosted Glass Orb with Specular Glint & Emerald Checkmark
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1.5)
                        
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.5), Color.white.opacity(0.1)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.8
                            )
                        
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(red: 0.18, green: 0.82, blue: 0.42))
                            .shadow(color: Color.green.opacity(0.4), radius: 3, y: 0.5)
                    }
                case .errors(let count, _, _):
                    // Luminous Ruby Gem with Specular Rim & Ambient Glow
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color(red: 1.0, green: 0.28, blue: 0.42),
                                        Color(red: 0.92, green: 0.14, blue: 0.28),
                                        Color(red: 0.78, green: 0.08, blue: 0.22)
                                    ],
                                    center: .topLeading,
                                    startRadius: 2,
                                    endRadius: 26
                                )
                            )
                            .shadow(color: Color(red: 0.95, green: 0.15, blue: 0.35).opacity(0.55), radius: 5, x: 0, y: 2)
                        
                        // Specular Glass Glint
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.7), Color.white.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.9
                            )
                        
                        Text("\(count)")
                            .font(.system(size: 11.5, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(color: Color.black.opacity(0.35), radius: 1, y: 0.5)
                    }
                }
            }
            .frame(width: 27, height: 27)
            .scaleEffect(isHovered ? 1.15 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            onHover(hovering)
        }
    }
}

// MARK: - SwiftUI Popover Card View (Liquid Glass Edition)

struct CornerBadgePopoverView: View {
    let issues: [CorrectionIssue]
    let sentenceCorrection: CorrectionSentence?
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            // Header with Apple Intelligence Siri Accent
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.98, green: 0.22, blue: 0.48),
                                    Color(red: 0.65, green: 0.32, blue: 0.98),
                                    Color(red: 0.18, green: 0.65, blue: 0.98)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 22, height: 22)
                        .shadow(color: Color(red: 0.65, green: 0.32, blue: 0.98).opacity(0.4), radius: 4, y: 1.5)
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Text("Writing Assistant")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                
                Spacer()
                
                HStack(spacing: 3) {
                    Text("\(issues.count)")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundColor(.accentColor)
                    Text(issues.count == 1 ? "suggestion" : "suggestions")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(
                    Capsule()
                        .fill(Color.accentColor.opacity(0.12))
                )
            }

            Divider()
                .opacity(0.3)

            // Full Sentence "Apply All" Glass Banner
            if let sentence = sentenceCorrection {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color(red: 0.98, green: 0.22, blue: 0.48), Color(red: 0.65, green: 0.32, blue: 0.98)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                            Text("All Suggestions")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.primary.opacity(0.9))
                        }
                        Text(sentence.corrected)
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(red: 0.18, green: 0.82, blue: 0.42))
                            .lineLimit(2)
                    }

                    Spacer(minLength: 4)

                    Button(action: {
                        onDismiss()
                        sentence.onApply()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 9.5))
                            Text("Apply All")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.35, green: 0.42, blue: 0.98),
                                    Color(red: 0.65, green: 0.32, blue: 0.98)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .shadow(color: Color(red: 0.45, green: 0.35, blue: 0.98).opacity(0.45), radius: 4, y: 1.5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(Color.white.opacity(0.35), lineWidth: 0.6)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(9)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(red: 0.45, green: 0.35, blue: 0.98).opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color(red: 0.65, green: 0.32, blue: 0.98).opacity(0.18), lineWidth: 0.8)
                        )
                )
            }

            // List of Individual Word Corrections
            if !issues.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(issues.prefix(4)) { issue in
                        HStack(alignment: .center, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                if !issue.original.isEmpty {
                                    Text(issue.original)
                                        .font(.system(size: 12, weight: .regular))
                                        .strikethrough()
                                        .foregroundColor(Color(red: 1.0, green: 0.32, blue: 0.32))
                                }
                                Text(issue.corrected)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(red: 0.18, green: 0.82, blue: 0.42))
                                if !issue.explanation.isEmpty {
                                    Text(issue.explanation)
                                        .font(.system(size: 9.5, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer(minLength: 4)

                            Button(action: {
                                onDismiss()
                                issue.onApply()
                            }) {
                                Text("Apply")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4.5)
                                    .background(.ultraThinMaterial)
                                    .foregroundColor(.primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(Color.primary.opacity(0.12), lineWidth: 0.6)
                                    )
                                    .shadow(color: Color.black.opacity(0.06), radius: 2, y: 1)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.035))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
                                )
                        )
                    }
                }
            }

            if issues.count > 4 {
                Text("+\(issues.count - 4) more suggestions")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.leading, 2)
            }
            
            // Sleek Pro Privacy Footer
            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary.opacity(0.7))
                Text("Private • On-Device AI Engine")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(.top, 2)
            .padding(.leading, 2)
        }
        .padding(14)
        .frame(minWidth: 285)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.25), radius: 18, x: 0, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.42),
                            Color.white.opacity(0.08),
                            Color.white.opacity(0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}
