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

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarController: MenuBarController?
    var preferencesWindow: NSWindow?
    var onboardingWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        let permissionManager = PermissionManager.shared
        permissionManager.checkPermissions()
        
        if permissionManager.hasAccessibilityPermission {
            initializeApp()
        } else {
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
    }
    
    @objc func openPreferences() {
        if preferencesWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 450),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "MacToys Preferences"
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
    
    var body: some View {
        VStack(spacing: 30) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 100, height: 100)
                .padding(.top, 20)
            
            Text("Welcome to MacToys")
                .font(.system(size: 28, weight: .bold))
            
            Text("To power global hotkeys, the Clipboard Manager, and Text Extractor, MacToys requires Accessibility permissions to interact with other apps.")
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
            
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "1.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                    VStack(alignment: .leading) {
                        Text("Open System Settings")
                            .font(.headline)
                        Text("Click the button below to open Privacy & Security settings.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "2.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                    VStack(alignment: .leading) {
                        Text("Enable MacToys")
                            .font(.headline)
                        Text("Find MacToys in the list and turn the toggle ON.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .padding(.horizontal, 30)
            
            Button(action: {
                openAccessibilitySettings()
            }) {
                Text("Open System Settings")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 24)
                    .background(Color.blue)
                    .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.top, 10)
            
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.5)
                Text("Waiting for permission...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 30)
        }
        .frame(width: 500, height: 550)
        .background(VisualEffectView().ignoresSafeArea())
        .onAppear {
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
