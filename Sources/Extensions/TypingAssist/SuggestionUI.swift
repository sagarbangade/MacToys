import Foundation
import AppKit
import SwiftUI

class SuggestionState: ObservableObject {
    @Published var suggestions: [String] = []
    @Published var selectedIndex: Int = 0
}

struct ShimmerText: View {
    let text: String
    @State private var phase: CGFloat = -1.0
    
    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundColor(.clear)
            .overlay(
                LinearGradient(
                    stops: [
                        .init(color: .cyan.opacity(0.8), location: 0.0),
                        .init(color: .blue, location: 0.3),
                        .init(color: .purple, location: 0.5),
                        .init(color: .pink, location: 0.7),
                        .init(color: .cyan.opacity(0.8), location: 1.0)
                    ],
                    startPoint: UnitPoint(x: phase, y: 0),
                    endPoint: UnitPoint(x: phase + 1, y: 0)
                )
                .mask(Text(text).font(.system(size: 14, weight: .bold, design: .rounded)))
            )
            .onAppear {
                withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                    phase = 1.0
                }
            }
            // Removed .id(text) to prevent SwiftUI recreation crashes
    }
}

struct SuggestionView: View {
    @ObservedObject var state: SuggestionState
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(state.suggestions.enumerated()), id: \.offset) { index, text in
                if index == state.selectedIndex {
                    ShimmerText(text: text)
                } else {
                    Text(text)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
        }
        .fixedSize() // Force SwiftUI to NOT truncate text
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            VisualEffectBlurView()
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
        )
        .padding(10) // padding so shadow doesn't clip
    }
}

// Helper to get raw NSVisualEffectView for the glassy look
struct VisualEffectBlurView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

@MainActor
public class SuggestionUI {
    public static let shared = SuggestionUI()

    private var panel: NSPanel?
    private let state = SuggestionState()
    
    private init() {
        setupPanel()
    }

    private func setupPanel() {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 60), // Start with a safe large size
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.animationBehavior = .none

        let hostingView = NSHostingView(rootView: SuggestionView(state: state))
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        // Tell NSHostingView not to restrict itself
        hostingView.autoresizingMask = [.width, .height]
        
        p.contentView = hostingView
        self.panel = p
    }

    public func show(suggestions: [String], selectedIndex: Int, at caretRect: CGRect?) {
        guard let panel = panel, !suggestions.isEmpty else { return }

        // Update state
        self.state.suggestions = suggestions
        self.state.selectedIndex = selectedIndex
        
        guard let screen = NSScreen.screens.first else { return }
        let screenH = screen.frame.height

        let hostingView = panel.contentView as! NSHostingView<SuggestionView>
        hostingView.layout() // Force layout synchronously
        
        let fittingSize = hostingView.fittingSize
        let safeWidth = max(fittingSize.width, 100)
        let safeHeight = max(fittingSize.height, 30)

        // Use provided caretRect or fallback
        let anchorRect = caretRect ?? CGRect(origin: NSEvent.mouseLocation, size: CGSize(width: 1, height: 20))
        
        // Position
        let x = anchorRect.origin.x + anchorRect.width
        let y: CGFloat
        if caretRect != nil {
            y = screenH - anchorRect.origin.y - anchorRect.height - safeHeight + 14
        } else {
            y = anchorRect.origin.y - safeHeight
        }

        panel.setFrame(NSRect(x: x, y: y, width: safeWidth, height: safeHeight), display: true)
        panel.orderFrontRegardless()
    }

    public func hide() {
        panel?.orderOut(nil)
    }
}
