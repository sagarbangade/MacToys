import SwiftUI
import UniformTypeIdentifiers
import KeyboardShortcuts
import MacToysKit

struct GrammarCheckerSettingsView: View {
    @AppStorage("gecBackendType") private var backendType: String = "local"
    @AppStorage("gecModelPath") private var modelPath: String = ""
    @AppStorage("gecApiProvider") private var apiProvider: String = "groq"
    @AppStorage("gecApiModel") private var apiModel: String = "groq/qwen/qwen3.8-27b"
    @AppStorage("gecApiKey") private var apiKey: String = ""
    @AppStorage("gecLoadOnStartup") private var loadOnStartup: Bool = true
    
    @State private var memoryStatus: String = "Ready"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            
            PremiumCard {
                PremiumRow(icon: "keyboard", iconColor: .blue, title: "Activation Shortcut", subtitle: "Select text in any app and press to fix grammar") {
                    KeyboardShortcuts.Recorder("", name: .grammarChecker)
                }
            }
            
            PremiumCard {
                PremiumRow(icon: "cpu", iconColor: .purple, title: "Engine", subtitle: "Choose between local offline AI or cloud API") {
                    Picker("", selection: $backendType) {
                        Text("Local Model").tag("local")
                        Text("Cloud API").tag("api")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
                
                PremiumDivider()
                
                if backendType == "local" {
                    PremiumRow(icon: "brain", iconColor: .indigo, title: "Local Model File", subtitle: "Select a .gguf offline model") {
                        HStack(spacing: 8) {
                            Text(modelPath.isEmpty ? "No model selected" : (modelPath as NSString).lastPathComponent)
                                .foregroundColor(modelPath.isEmpty ? .secondary : .primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 160, alignment: .trailing)
                                .help(modelPath.isEmpty ? "" : modelPath) // Show full path on hover
                            
                            Button("Browse...") {
                                selectFile()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    
                    PremiumDivider()
                    
                    PremiumRow(icon: "memorychip", iconColor: .orange, title: "Memory Management", subtitle: memoryStatus) {
                        HStack(spacing: 12) {
                            Button("Load to RAM") {
                                memoryStatus = "Loading local model..."
                                Task {
                                    await GECSidecar.shared.sendCommand("load_local")
                                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                                    memoryStatus = "Model loaded in memory"
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            
                            Button("Stop / Clear RAM") {
                                memoryStatus = "Clearing memory..."
                                Task {
                                    await GECSidecar.shared.sendCommand("unload_local")
                                    try? await Task.sleep(nanoseconds: 500_000_000)
                                    memoryStatus = "Memory cleared"
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    
                    PremiumDivider()
                    
                    PremiumRow(icon: "bolt.fill", iconColor: .yellow, title: "Preload on Startup", subtitle: "Automatically load model when Grammar Checker is turned on") {
                        Toggle("", isOn: $loadOnStartup)
                            .toggleStyle(.switch)
                    }
                    
                } else {
                    PremiumRow(icon: "network", iconColor: .green, title: "API Provider", subtitle: "Select your LLM provider") {
                        Picker("", selection: $apiProvider) {
                            Text("Groq").tag("groq")
                            Text("OpenAI").tag("openai")
                            Text("Anthropic").tag("anthropic")
                            Text("Gemini").tag("gemini")
                        }
                        .frame(width: 150)
                    }
                    
                    PremiumDivider()
                    
                    PremiumRow(icon: "server.rack", iconColor: .orange, title: "Model Name", subtitle: "e.g., groq/qwen/qwen3.8-27b") {
                        TextField("Model Name", text: $apiModel)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 250)
                    }
                    
                    PremiumDivider()
                    
                    PremiumRow(icon: "key", iconColor: .red, title: "API Key", subtitle: "Your secret authentication token") {
                        SecureField("sk-...", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 250)
                    }
                }
            }
            
            if backendType == "local" {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    Text("The local model will stay in memory for fast execution unless you click Stop.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
            }
        }
    }
    
    private func selectFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                modelPath = url.path
            }
        }
    }
}
