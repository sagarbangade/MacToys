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
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("SLEEP PREVENTION CONFIGURATION")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                
                PremiumCard {
                    PremiumRow(
                        icon: "sun.max.fill",
                        iconColor: .yellow,
                        title: "Prevention Mode",
                        subtitle: "Control whether displays and system sleep are blocked"
                    ) {
                        Picker("", selection: $mode) {
                            ForEach(SleepPreventionMode.allCases) { m in
                                Text(m.rawValue).tag(m)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 190)
                        .onChange(of: mode) { _, _ in
                            module.restartAssertionIfNeeded()
                        }
                    }
                    
                    PremiumDivider()
                    
                    PremiumRow(
                        icon: "bolt.badge.clock.fill",
                        iconColor: .orange,
                        title: "Quick Access",
                        subtitle: "Toggle Keep Awake instantly from the MacToys menu bar"
                    ) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 16))
                    }
                }
            }
        }
    }
}
