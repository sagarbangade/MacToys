import SwiftUI
import AppKit

@MainActor
public final class GrammarCheckerUI {
    public static let shared = GrammarCheckerUI()

    private var panel: NSPanel?
    private var hostingController: NSHostingController<GrammarCheckerView>?

    private init() {}

    public func show(originalText: String) {
        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 250),
                styleMask: [.nonactivatingPanel, .fullSizeContentView, .titled, .closable],
                backing: .buffered,
                defer: false
            )
            p.isFloatingPanel = true
            p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.titlebarAppearsTransparent = true
            p.titleVisibility = .hidden
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.center()
            panel = p
        }
        
        let hc = NSHostingController(rootView: GrammarCheckerView(originalText: originalText))
        panel?.contentView = hc.view
        self.hostingController = hc
        
        panel?.makeKeyAndOrderFront(nil)
    }

    public func hide() {
        panel?.orderOut(nil)
        NSApp.hide(nil)
    }
}

struct GrammarCheckerView: View {
    let originalText: String
    
    @State private var correctedText: String = ""
    @State private var isProcessing: Bool = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "wand.and.stars")
                    .foregroundColor(.purple)
                Text("Grammar Fixer")
                    .font(.headline)
                Spacer()
                if isProcessing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            
            Divider()
            
            ScrollView {
                Text(correctedText.isEmpty ? originalText : correctedText)
                    .font(.body)
                    .foregroundColor(correctedText.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 150)
            
            Divider()
            
            HStack {
                Button("Cancel") {
                    GrammarCheckerService.shared.cancel()
                    GrammarCheckerUI.shared.hide()
                    LocalAIEngine.shared.cancelLoading()
                }
                .keyboardShortcut(.escape, modifiers: [])
                
                Spacer()
                
                Button("Replace") {
                    GrammarCheckerService.shared.replaceSelectedText(with: correctedText)
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing || correctedText.isEmpty)
            }
        }
        .padding()
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        )
        .onAppear {
            startProcessing()
        }
    }
    
    private func startProcessing() {
        correctedText = ""
        isProcessing = true
        
        Task {
            do {
                // Start the GEC sidecar (loads CoEdit-Large T5 model)
                try await GECSidecar.shared.start()
                
                let lines = originalText.components(separatedBy: "\n")
                var resultLines: [String] = []
                
                for line in lines {
                    if line.trimmingCharacters(in: .whitespaces).isEmpty {
                        resultLines.append(line)
                        continue
                    }
                    
                    let corrected = try await GECSidecar.shared.correct(text: line)
                    resultLines.append(corrected)
                    
                    // Update UI progressively
                    DispatchQueue.main.async {
                        self.correctedText = resultLines.joined(separator: "\n")
                    }
                }
                
                DispatchQueue.main.async {
                    self.correctedText = resultLines.joined(separator: "\n")
                    self.isProcessing = false
                }
            } catch {
                print("GEC Error: \(error)")
                DispatchQueue.main.async {
                    self.correctedText = self.originalText
                    self.isProcessing = false
                }
            }
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
