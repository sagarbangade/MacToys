import Foundation
import Cocoa
import SwiftUI
import IOKit.pwr_mgt
import MacToysKit
import KeyboardShortcuts

public enum SleepPreventionMode: String, CaseIterable, Identifiable {
    case display = "Keep display and system awake"
    case system = "Keep system awake (allow display to sleep)"
    
    public var id: String { self.rawValue }
    
    var assertionType: CFString {
        switch self {
        case .display: return kIOPMAssertionTypeNoDisplaySleep as CFString
        case .system: return kIOPMAssertionTypePreventUserIdleSystemSleep as CFString
        }
    }
}

@MainActor
public final class KeepAwakeModule: UtilityModule {
    public let id = "keepAwake"
    public let displayName = "Keep Awake"
    public let description = "Prevent your Mac from going to sleep"
    public let iconSymbol = "cup.and.saucer"
    
    public var isEnabled: Bool = false
    public let requiredPermissions: [PermissionRequirement] = []
    public var shortcutName: KeyboardShortcuts.Name? { nil }
    
    private var assertionID: IOPMAssertionID = 0
    private var isAsserting = false
    
    public init() {}
    
    public func triggerAction() {
        // Keep awake doesn't have a specific momentary action.
        // Toggling happens via the switch.
    }
    
    public func start() {
        preventSleep()
    }
    
    public func stop() {
        allowSleep()
    }
    
    public func makeSettingsView() -> AnyView {
        AnyView(KeepAwakeSettingsView(module: self))
    }
    
    public func restartAssertionIfNeeded() {
        if isEnabled {
            allowSleep()
            preventSleep()
        }
    }
    
    private func preventSleep() {
        guard !isAsserting else { return }
        
        let modeStr = UserDefaults.standard.string(forKey: "keepAwakeMode") ?? SleepPreventionMode.display.rawValue
        let mode = SleepPreventionMode(rawValue: modeStr) ?? .display
        
        let success = IOPMAssertionCreateWithName(
            mode.assertionType,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "MacToys Keep Awake" as CFString,
            &assertionID
        )
        
        if success == kIOReturnSuccess {
            isAsserting = true
            print("Sleep prevented (\(mode))")
        } else {
            print("Failed to prevent sleep")
        }
    }
    
    private func allowSleep() {
        guard isAsserting else { return }
        IOPMAssertionRelease(assertionID)
        isAsserting = false
        print("Sleep allowed")
    }
}

struct KeepAwakeSettingsView: View {
    let module: KeepAwakeModule
    @AppStorage("keepAwakeMode") private var mode: SleepPreventionMode = .display
    
    var body: some View {
        Form {
            Picker("Mode:", selection: $mode) {
                ForEach(SleepPreventionMode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .onChange(of: mode) { _, _ in
                // Restart assertion with new mode if it's currently active
                module.restartAssertionIfNeeded()
            }
            
            Text("When enabled in the main menu, your Mac will stay awake.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}
