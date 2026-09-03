import SwiftUI
import MacToysKit

struct PreferencesView: View {
    @ObservedObject var registry = ModuleRegistry.shared
    @State private var selectedModuleID: String?
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedModuleID) {
                Section("Utilities") {
                    ForEach(registry.modules, id: \.id) { module in
                        NavigationLink(value: module.id) {
                            Label(module.displayName, systemImage: module.iconSymbol)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 180, max: 200)
        } detail: {
            if let selectedModuleID = selectedModuleID,
               let module = registry.modules.first(where: { $0.id == selectedModuleID }) {
                
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack(spacing: 16) {
                        Image(systemName: module.iconSymbol)
                            .font(.system(size: 32))
                            .foregroundColor(.accentColor)
                            .frame(width: 48, height: 48)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(12)
                            .shadow(color: Color.black.opacity(0.1), radius: 2, y: 1)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(module.displayName)
                                .font(.title2)
                                .fontWeight(.semibold)
                            Text(module.description)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        
                        let isEnabledBinding = Binding<Bool>(
                            get: { module.isEnabled },
                            set: { newValue in
                                registry.toggleModule(module, enabled: newValue)
                            }
                        )
                        
                        Toggle("", isOn: isEnabledBinding)
                            .toggleStyle(.switch)
                            .scaleEffect(1.2)
                    }
                    .padding(24)
                    .background(Color(NSColor.windowBackgroundColor))
                    
                    Divider()
                    
                    // Settings Content
                    module.makeSettingsView()
                        .padding()
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(NSColor.textBackgroundColor))
                
            } else {
                VStack {
                    Image(systemName: "gearshape")
                        .font(.system(size: 48))
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    Text("Select a module to configure")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
            }
        }
        .frame(width: 700, height: 450)
        .onAppear {
            if selectedModuleID == nil {
                selectedModuleID = registry.modules.first?.id
            }
        }
    }
}
