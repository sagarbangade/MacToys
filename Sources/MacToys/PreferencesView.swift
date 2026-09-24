import SwiftUI
import MacToysKit

struct PreferencesView: View {
    @ObservedObject var registry = ModuleRegistry.shared
    @State private var settingsStore = SettingsStore.shared
    @State private var selectedModuleID: String? = "appearance"
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selectedModuleID) {
                Section("Personalization") {
                    NavigationLink(value: "appearance") {
                        SidebarRow(
                            title: "Appearance & Glass",
                            icon: "sparkles",
                            colors: [
                                Color(red: 0.98, green: 0.22, blue: 0.48),
                                Color(red: 0.65, green: 0.32, blue: 0.98),
                                Color(red: 0.18, green: 0.65, blue: 0.98)
                            ]
                        )
                    }
                }
                
                Section("Utilities") {
                    ForEach(registry.modules, id: \.id) { module in
                        NavigationLink(value: module.id) {
                            let info = moduleVisualInfo(for: module)
                            SidebarRow(
                                title: module.displayName,
                                icon: info.icon,
                                colors: info.colors,
                                isEnabled: module.isEnabled
                            )
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 220, ideal: 245, max: 280)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            ZStack {
                Color(NSColor.windowBackgroundColor).ignoresSafeArea()
                
                if selectedModuleID == "appearance" {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            // Header
                            ZStack(alignment: .bottomLeading) {
                                MeshGradientBackground()
                                    .frame(height: 140)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .shadow(color: Color.black.opacity(0.18), radius: 12, y: 5)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                                
                                HStack(alignment: .center, spacing: 16) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(.ultraThinMaterial)
                                            .frame(width: 68, height: 68)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                    .stroke(Color.white.opacity(0.4), lineWidth: 1)
                                            )
                                            .shadow(color: Color.black.opacity(0.25), radius: 8, y: 4)
                                        
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 32, weight: .bold))
                                            .foregroundStyle(SiriGlow.chromaticGradient)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Liquid Glass Theme")
                                            .font(.system(size: 24, weight: .bold, design: .rounded))
                                            .foregroundColor(.white)
                                            .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                                        
                                        Text("macOS 27 Glassmorphism & Apple Intelligence Vibe")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.white.opacity(0.92))
                                            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                                    }
                                    
                                    Spacer()
                                }
                                .padding(20)
                            }
                            
                            // Theme Selector Cards
                            VStack(alignment: .leading, spacing: 10) {
                                Text("THEME STYLE")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 4)
                                
                                AppearancePickerView(currentTheme: $settingsStore.appearance)
                            }
                            
                            // App Preferences Card
                            VStack(alignment: .leading, spacing: 10) {
                                Text("SYSTEM & INTEGRATION")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 4)
                                
                                PremiumCard {
                                    PremiumRow(
                                        icon: "arrow.up.circle.fill",
                                        iconColor: .indigo,
                                        title: "Launch at Login",
                                        subtitle: "Automatically start MacToys in the menu bar when your Mac turns on"
                                    ) {
                                        Toggle("", isOn: $settingsStore.launchAtLogin)
                                            .toggleStyle(.switch)
                                    }
                                    
                                    PremiumDivider()
                                    
                                    PremiumRow(
                                        icon: "menubar.rectangle",
                                        iconColor: .teal,
                                        title: "Menu Bar Icon",
                                        subtitle: "Display MacToys quick access icon in the macOS menu bar"
                                    ) {
                                        Toggle("", isOn: $settingsStore.showMenuBarIcon)
                                            .toggleStyle(.switch)
                                    }
                                }
                            }
                            
                            // Pro Design Badge
                            HStack(spacing: 12) {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 18))
                                    .foregroundStyle(SiriGlow.chromaticGradient)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Designed for macOS Tahoe & Sequoia")
                                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                    Text("Featuring specular glass highlights, GPU-accelerated blur, and on-device privacy.")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                                    )
                            )
                            
                            Spacer(minLength: 40)
                        }
                        .padding(24)
                    }
                    .transition(.opacity)
                } else if let selectedModuleID = selectedModuleID,
                   let module = registry.modules.first(where: { $0.id == selectedModuleID }) {
                    
                    let visual = moduleVisualInfo(for: module)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            // Premium Header
                            ZStack(alignment: .bottomLeading) {
                                MeshGradientBackground(color1: visual.gradientStart, color2: visual.gradientEnd)
                                    .frame(height: 130)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .shadow(color: Color.black.opacity(0.16), radius: 12, y: 5)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                                
                                HStack(alignment: .center, spacing: 16) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(.ultraThinMaterial)
                                            .frame(width: 64, height: 64)
                                            .shadow(color: Color.black.opacity(0.2), radius: 8, y: 4)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
                                            )
                                        
                                        Image(systemName: visual.icon)
                                            .font(.system(size: 30, weight: .semibold))
                                            .foregroundColor(.white)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(module.displayName)
                                            .font(.system(size: 22, weight: .bold, design: .rounded))
                                            .foregroundColor(.white)
                                            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                                        
                                        Text(module.description)
                                            .font(.system(size: 12.5, weight: .medium))
                                            .foregroundColor(.white.opacity(0.92))
                                            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                                            .lineLimit(2)
                                    }
                                    
                                    Spacer()
                                    
                                    HStack(spacing: 8) {
                                        Text(module.isEnabled ? "ACTIVE" : "INACTIVE")
                                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                            .foregroundColor(module.isEnabled ? .green : .white.opacity(0.7))
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(
                                                Capsule()
                                                    .fill(module.isEnabled ? Color.green.opacity(0.18) : Color.black.opacity(0.25))
                                            )
                                        
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
                                            .labelsHidden()
                                    }
                                }
                                .padding(20)
                            }
                            
                            // Settings Content
                            module.makeSettingsView()
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            
                            Spacer(minLength: 40)
                        }
                        .padding(24)
                    }
                    .id(selectedModuleID)
                    .transition(.opacity)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "sparkles.square.filled.on.square")
                            .font(.system(size: 64))
                            .foregroundStyle(SiriGlow.chromaticGradient)
                        Text("MacToys Settings")
                            .font(.title)
                            .fontWeight(.bold)
                        Text("Select a utility or customize appearance from the sidebar.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedModuleID)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .frame(minWidth: 840, idealWidth: 860, minHeight: 600, idealHeight: 640)
        .background(WindowConfigurator())
        .onAppear {
            if selectedModuleID == nil {
                selectedModuleID = "appearance"
            }
        }
    }
}

// MARK: - AppKit Window Configurator to eliminate collapse button

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            
            // Remove sidebar toggle item from toolbar if present
            if let toolbar = window.toolbar {
                for (index, item) in toolbar.items.enumerated().reversed() {
                    let id = item.itemIdentifier.rawValue.lowercased()
                    if id.contains("sidebartoggle") || id.contains("togglesidebar") || id.contains("sidebar") {
                        toolbar.removeItem(at: index)
                    }
                }
            }
            
            // Remove title text from titlebar for cleaner Tahoe glass aesthetic
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Visual Helpers

struct SidebarRow: View {
    let title: String
    let icon: String
    let colors: [Color]
    var isEnabled: Bool? = nil
    
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 22, height: 22)
                    .shadow(color: colors.first?.opacity(0.3) ?? .clear, radius: 2, y: 1)
                
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            Text(title)
                .font(.system(size: 13, weight: .regular, design: .rounded))
            
            Spacer()
            
            if let isEnabled = isEnabled, isEnabled {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                    .shadow(color: Color.green.opacity(0.4), radius: 2)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ModuleVisualInfo {
    let icon: String
    let gradientStart: Color
    let gradientEnd: Color
    let colors: [Color]
}

@MainActor
func moduleVisualInfo(for module: any UtilityModule) -> ModuleVisualInfo {
    switch module.id {
    case "textExtractor":
        return ModuleVisualInfo(icon: "text.viewfinder", gradientStart: .blue, gradientEnd: .indigo, colors: [.blue, .indigo])
    case "colorPicker":
        return ModuleVisualInfo(icon: "eyedropper.halffull", gradientStart: .orange, gradientEnd: .pink, colors: [.orange, .pink])
    case "keepAwake":
        return ModuleVisualInfo(icon: "sun.max.fill", gradientStart: .yellow, gradientEnd: .orange, colors: [.yellow, .orange])
    case "screenRuler":
        return ModuleVisualInfo(icon: "ruler.fill", gradientStart: .purple, gradientEnd: .indigo, colors: [.purple, .indigo])
    case "clipboard":
        return ModuleVisualInfo(icon: "doc.on.clipboard.fill", gradientStart: Color(red: 0.1, green: 0.45, blue: 0.95), gradientEnd: Color(red: 0.35, green: 0.2, blue: 0.85), colors: [.blue, .cyan])
    case "qrScanner":
        return ModuleVisualInfo(icon: "qrcode.viewfinder", gradientStart: .mint, gradientEnd: .teal, colors: [.mint, .teal])
    case "mobileScanner":
        return ModuleVisualInfo(icon: "iphone.badge.play", gradientStart: .cyan, gradientEnd: .blue, colors: [.cyan, .blue])
    case "typingAssist":
        return ModuleVisualInfo(icon: "keyboard.fill", gradientStart: .teal, gradientEnd: .indigo, colors: [.teal, .blue])
    case "spellChecker":
        return ModuleVisualInfo(icon: "textformat.abc", gradientStart: Color(red: 0.95, green: 0.25, blue: 0.4), gradientEnd: Color(red: 0.9, green: 0.45, blue: 0.2), colors: [.red, .orange])
    case "grammarChecker":
        return ModuleVisualInfo(icon: "sparkles.rectangle.stack.fill", gradientStart: Color(red: 0.65, green: 0.3, blue: 0.95), gradientEnd: Color(red: 0.2, green: 0.5, blue: 0.98), colors: [.purple, .blue])
    default:
        return ModuleVisualInfo(icon: module.iconSymbol, gradientStart: .blue, gradientEnd: .purple, colors: [.blue, .purple])
    }
}
