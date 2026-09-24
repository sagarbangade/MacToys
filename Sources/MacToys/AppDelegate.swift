import AppKit
import SwiftUI
import Combine
import MacToysKit
import TextExtractor
import ColorPicker
import KeepAwake
import ScreenRuler
import ClipboardManager
import QRScanner
import MobileScanner
import TypingAssist
import SpellChecker
import GrammarChecker

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarController: MenuBarController?
    var preferencesWindow: NSWindow?
    var onboardingWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    
    override init() {
        super.init()
        // Fix for MLX Swift not finding the statically linked metallib
        if let metallibPath = Bundle.main.url(forResource: "default", withExtension: "metallib")?.path {
            setenv("METAL_LIBRARY_PATH", metallibPath, 1)
        }
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        let permissionManager = PermissionManager.shared
        permissionManager.checkPermissions()
        print("[MacToys] Launch: hasAccessibilityPermission=\(permissionManager.hasAccessibilityPermission)")
        
        if permissionManager.hasAccessibilityPermission {
            initializeApp()
        } else {
            permissionManager.requestAccessibilityPermission()
            showOnboarding()
            
            NotificationCenter.default.publisher(for: .accessibilityPermissionGranted)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    self?.closeOnboardingAndInitializeApp()
                }
                .store(in: &cancellables)
        }
    }
    
    private func showOnboarding() {
        if onboardingWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 550),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Welcome to MacToys"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.center()
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: OnboardingView())
            onboardingWindow = window
        }
        
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }
    
    private func closeOnboardingAndInitializeApp() {
        onboardingWindow?.close()
        onboardingWindow = nil
        initializeApp()
    }
    
    private func initializeApp() {
        setupModules()
        menuBarController = MenuBarController()
        print("MacToys started successfully.")
        
        let hasLaunched = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        if !hasLaunched {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            openPreferences()
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if PermissionManager.shared.hasAccessibilityPermission {
            openPreferences()
        } else {
            showOnboarding()
        }
        return true
    }
    
    private func setupModules() {
        ModuleRegistry.shared.register(TextExtractorModule())
        ModuleRegistry.shared.register(ColorPickerModule())
        ModuleRegistry.shared.register(KeepAwakeModule())
        ModuleRegistry.shared.register(ScreenRulerModule())
        ModuleRegistry.shared.register(ClipboardModule())
        ModuleRegistry.shared.register(QRScannerModule())
        ModuleRegistry.shared.register(MobileScannerModule())
        ModuleRegistry.shared.register(TypingAssistModule.shared)
        ModuleRegistry.shared.register(SpellCheckerModule.shared)
        ModuleRegistry.shared.register(GrammarCheckerModule.shared)
    }
    
    @objc func openPreferences() {
        if #available(macOS 14.0, *) {
            if NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
                NSApp.activate(ignoringOtherApps: true)
                return
            }
        }
        if NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil) {
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        if preferencesWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 840, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "MacToys Settings"
            window.titlebarAppearsTransparent = true
            window.center()
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: PreferencesView())
            preferencesWindow = window
        }
        
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }
}

struct OnboardingView: View {
    @StateObject private var permissionManager = PermissionManager.shared
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            // Background
            MeshGradientBackground(color1: Color.blue, color2: Color.purple)
                .ignoresSafeArea()
            
            VisualEffectView().ignoresSafeArea()
            
            VStack(spacing: 32) {
                // Icon Header
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 140, height: 140)
                        .blur(radius: 10)
                        .scaleEffect(isAnimating ? 1.05 : 0.95)
                        .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: isAnimating)
                    
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .frame(width: 100, height: 100)
                        .shadow(color: .black.opacity(0.3), radius: 15, y: 10)
                }
                .padding(.top, 20)
                
                VStack(spacing: 8) {
                    Text("Welcome to MacToys")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    
                    Text("Supercharge your Mac with global hotkeys,\nAI grammar correction, and text extraction.")
                        .font(.system(size: 16, weight: .medium))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                        .padding(.horizontal, 40)
                }
                
                // Instructions Card
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: "1.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Open System Settings")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                            Text("Click the button below to open Privacy & Security.")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(20)
                    
                    Divider().padding(.leading, 60)
                    
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: "2.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Enable MacToys")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                            Text("Find MacToys in the list and turn the toggle ON.")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(20)
                }
                .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
                .padding(.horizontal, 40)
                
                // Action Button
                Button(action: {
                    openAccessibilitySettings()
                }) {
                    Text("Open System Settings")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(colors: [Color.blue, Color.purple.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .blue.opacity(0.3), radius: 8, y: 4)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 40)
                .padding(.top, 10)
                
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                        .colorScheme(.dark)
                    Text("Waiting for permission...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.bottom, 20)
            }
        }
        .frame(width: 550, height: 650)
        .onAppear {
            isAnimating = true
            permissionManager.requestAccessibilityPermission()
            permissionManager.startMonitoringAccessibility()
        }
        .onDisappear {
            permissionManager.stopMonitoringAccessibility()
        }
    }
    
    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .windowBackground
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
