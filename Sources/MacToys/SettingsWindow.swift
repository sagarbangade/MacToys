import SwiftUI
import MacToysKit
import KeyboardShortcuts

struct SettingsWindow: View {
    @ObservedObject var registry = ModuleRegistry.shared
    @State private var hoveredModuleId: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("MacToys")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Image(systemName: "power")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            Divider()
            
            // Modules List
            VStack(spacing: 4) {
                ForEach(registry.modules, id: \.id) { module in
                    HStack {
                        // The clickable area for the trigger action
                        Button(action: {
                            if module.isEnabled {
                                module.triggerAction()
                                // Attempt to close popover
                                NSApp.sendAction(#selector(NSPopover.performClose(_:)), to: nil, from: nil)
                            }
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: module.iconSymbol)
                                    .font(.system(size: 16))
                                    .foregroundColor(module.isEnabled ? .accentColor : .secondary)
                                    .frame(width: 24)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(module.displayName)
                                        .font(.headline)
                                        .foregroundColor(module.isEnabled ? .primary : .secondary)
                                    Text(module.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if module.isEnabled, let shortcutName = module.shortcutName {
                                    if let shortcut = KeyboardShortcuts.getShortcut(for: shortcutName) {
                                        Text(shortcut.description)
                                            .font(.system(.caption, design: .rounded))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color(NSColor.tertiarySystemFill))
                                            .cornerRadius(4)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // The toggle switch (isolated from the main row button)
                        let isEnabledBinding = Binding<Bool>(
                            get: { module.isEnabled },
                            set: { newValue in
                                registry.toggleModule(module, enabled: newValue)
                            }
                        )
                        Toggle("", isOn: isEnabledBinding)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .padding(.leading, 8)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(hoveredModuleId == module.id ? Color(NSColor.quaternarySystemFill) : Color.clear)
                    .cornerRadius(8)
                    .onHover { isHovered in
                        if isHovered {
                            hoveredModuleId = module.id
                        } else if hoveredModuleId == module.id {
                            hoveredModuleId = nil
                        }
                    }
                }
            }
            .padding(8)
            
            Divider()
            
            // Footer
            HStack {
                Button("Preferences...") {
                    NSApp.sendAction(#selector(AppDelegate.openPreferences), to: nil, from: nil)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .onHover { isHovered in
                    // Simple hover effect could go here, but native .plain button is okay
                }
                
                Spacer()
                Text("v1.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 380)
    }
}
