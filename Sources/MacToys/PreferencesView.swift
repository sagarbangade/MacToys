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
                            Label {
                                Text(module.displayName)
                                    .font(.system(size: 14, weight: .medium))
                            } icon: {
                                Image(systemName: module.iconSymbol)
                                    .foregroundStyle(Color.accentColor.gradient)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .background(VisualEffectView().ignoresSafeArea())
        } detail: {
            ZStack {
                Color(NSColor.underPageBackgroundColor).ignoresSafeArea()
                
                if let selectedModuleID = selectedModuleID,
                   let module = registry.modules.first(where: { $0.id == selectedModuleID }) {
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            // Premium Header
                            ZStack(alignment: .bottomLeading) {
                                MeshGradientBackground(color1: Color.blue, color2: Color.purple)
                                    .frame(height: 160)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .shadow(color: Color.black.opacity(0.1), radius: 10, y: 5)
                                
                                HStack(alignment: .bottom) {
                                    Image(systemName: module.iconSymbol)
                                        .font(.system(size: 40))
                                        .foregroundStyle(.white)
                                        .frame(width: 80, height: 80)
                                        .background(
                                            LinearGradient(colors: [Color.white.opacity(0.3), Color.white.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                        .shadow(color: Color.black.opacity(0.2), radius: 10, y: 5)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                                .stroke(Color.white.opacity(0.5), lineWidth: 1)
                                        )
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(module.displayName)
                                            .font(.system(size: 28, weight: .bold))
                                            .foregroundColor(.white)
                                            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                                        
                                        Text(module.description)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.white.opacity(0.9))
                                            .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                                    }
                                    .padding(.leading, 12)
                                    .padding(.bottom, 8)
                                    
                                    Spacer()
                                    
                                    let isEnabledBinding = Binding<Bool>(
                                        get: { module.isEnabled },
                                        set: { newValue in
                                            withAnimation(.spring()) {
                                                registry.toggleModule(module, enabled: newValue)
                                            }
                                        }
                                    )
                                    
                                    Toggle("", isOn: isEnabledBinding)
                                        .toggleStyle(.switch)
                                        .scaleEffect(1.2)
                                        .padding(.bottom, 16)
                                        .padding(.trailing, 16)
                                }
                                .padding(24)
                            }
                            
                            // Settings Content
                            module.makeSettingsView()
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            
                            Spacer(minLength: 40)
                        }
                        .padding(24)
                    }
                    .id(selectedModuleID) // Forces unique transition per module
                    .transition(.opacity)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "sparkles.square.filled.on.square")
                            .font(.system(size: 64))
                            .foregroundStyle(Color.accentColor.gradient)
                        Text("MacToys Settings")
                            .font(.title)
                            .fontWeight(.bold)
                        Text("Select a utility from the sidebar to configure it.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: selectedModuleID)
        }
        .frame(width: 800, height: 600)
        .onAppear {
            if selectedModuleID == nil {
                selectedModuleID = registry.modules.first?.id
            }
        }
    }
}

