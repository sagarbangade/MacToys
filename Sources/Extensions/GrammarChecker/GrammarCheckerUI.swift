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
    @State private var customInstruction: String = ""
    @State private var showCustomInput: Bool = false
    
    let toneOptions = ["Professional", "Casual", "Academic", "Enthusiastic", "Concise", "Persuasive"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "wand.and.stars")
                    .foregroundColor(.purple)
                Text("AI Assistant")
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
            .frame(maxHeight: 180)
            
            if showCustomInput {
                HStack {
                    TextField("E.g. Make it sound like a pirate...", text: $customInstruction)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            guard !customInstruction.isEmpty else { return }
                            startProcessing(instruction: customInstruction)
                        }
                    Button("Apply") {
                        startProcessing(instruction: customInstruction)
                    }
                    .disabled(customInstruction.isEmpty || isProcessing)
                    
                    Button(action: { showCustomInput = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button(action: { showCustomInput = true }) {
                            Label("Custom", systemImage: "pencil")
                        }
                        
                        Button("Rephrase") {
                            startProcessing(instruction: "Rephrase this text to flow more naturally.")
                        }
                        
                        Button("Rewrite") {
                            startProcessing(instruction: "Rewrite this text completely for better impact and clarity.")
                        }
                        
                        Menu("Change Tone") {
                            ForEach(toneOptions, id: \.self) { tone in
                                Button(tone) {
                                    startProcessing(instruction: "Change the tone of this text to \(tone). Keep the original meaning and structure (e.g. if it is a question, keep it a question).")
                                }
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isProcessing)
                }
            }
            
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
    
    private func startProcessing(instruction: String = "") {
        correctedText = ""
        isProcessing = true
        
        Task {
            do {
                try await GECSidecar.shared.start()
                
                if instruction.isEmpty {
                    // Line by line grammar check
                    let lines = originalText.components(separatedBy: "\n")
                    var resultLines: [String] = []
                    
                    for line in lines {
                        if line.trimmingCharacters(in: .whitespaces).isEmpty {
                            resultLines.append(line)
                            continue
                        }
                        
                        let corrected = try await GECSidecar.shared.correct(text: line, instruction: "")
                        resultLines.append(corrected)
                        
                        DispatchQueue.main.async {
                            self.correctedText = resultLines.joined(separator: "\n")
                        }
                    }
                    DispatchQueue.main.async {
                        self.isProcessing = false
                    }
                } else {
                    // Process whole block at once for rewrites
                    let result = try await GECSidecar.shared.correct(text: originalText, instruction: instruction)
                    DispatchQueue.main.async {
                        self.correctedText = result
                        self.isProcessing = false
                    }
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
