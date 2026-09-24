import SwiftUI
import MacToysKit
import KeyboardShortcuts

struct SettingsWindow: View {
    @ObservedObject var registry = ModuleRegistry.shared
    @State private var settingsStore = SettingsStore.shared
    @State private var hoveredModuleId: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with Apple Intelligence Siri Aesthetic
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(SiriGlow.chromaticGradient)
                        .frame(width: 32, height: 32)
                        .shadow(color: Color(red: 0.65, green: 0.32, blue: 0.98).opacity(0.4), radius: 6, y: 2)
                    
                    Image(systemName: "infinity")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("MacToys")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text("PRO")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.accentColor.opacity(0.2))
                            .foregroundColor(.accentColor)
                            .clipShape(Capsule())
                    }
                    
                    Text("Liquid Glass Edition")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Image(systemName: "power")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 26, height: 26)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Quit MacToys")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)
            
            Divider()
                .opacity(0.3)
            
            // Modules List
            VStack(spacing: 4) {
                ForEach(registry.modules, id: \.id) { module in
                    HStack {
                        Button(action: {
                            if module.isEnabled {
                                module.triggerAction()
                                NSApp.sendAction(#selector(NSPopover.performClose(_:)), to: nil, from: nil)
                            }
                        }) {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(module.isEnabled ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
                                    
                                    Image(systemName: module.iconSymbol)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(module.isEnabled ? .accentColor : .secondary)
                                }
                                .frame(width: 28, height: 28)
                                
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(module.displayName)
                                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                                        .foregroundColor(module.isEnabled ? .primary : .secondary)
                                    Text(module.description)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if module.isEnabled, let shortcutName = module.shortcutName {
                                    if let shortcut = KeyboardShortcuts.getShortcut(for: shortcutName) {
                                        Text(shortcut.description)
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 2.5)
                                            .background(
                                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                    .fill(.ultraThinMaterial)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                            .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                                                    )
                                            )
                                            .foregroundColor(.primary.opacity(0.85))
                                    }
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        
                        let isEnabledBinding = Binding<Bool>(
                            get: { module.isEnabled },
                            set: { newValue in
                                registry.toggleModule(module, enabled: newValue)
                            }
                        )
                        Toggle("", isOn: isEnabledBinding)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .scaleEffect(0.9)
                            .padding(.leading, 6)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(
                        hoveredModuleId == module.id
                        ? RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                        : RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.clear)
                    )
                    .onHover { isHovered in
                        hoveredModuleId = isHovered ? module.id : nil
                    }
                }
            }
            .padding(10)
            
            Divider()
                .opacity(0.3)
            
            // Footer
            HStack {
                Button(action: {
                    NSApp.sendAction(#selector(AppDelegate.openPreferences), to: nil, from: nil)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 11))
                        Text("Preferences...")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: settingsStore.appearance.icon)
                        .font(.system(size: 10))
                        .foregroundStyle(SiriGlow.chromaticGradient)
                    Text(settingsStore.appearance.title)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(0.04))
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
        .frame(width: 390)
    }
}
