import Foundation
import SwiftUI

@MainActor
public final class ModuleRegistry: ObservableObject {
    public static let shared = ModuleRegistry()
    
    @Published public private(set) var modules: [any UtilityModule] = []
    
    private init() {}
    
    public func register(_ module: any UtilityModule) {
        modules.append(module)
        
        // Restore state from settings
        let isEnabled = SettingsStore.shared.isModuleEnabled(id: module.id)
        module.isEnabled = isEnabled
        
        if isEnabled {
            module.start()
        }
    }
    
    public func toggleModule(_ module: any UtilityModule, enabled: Bool) {
        module.isEnabled = enabled
        SettingsStore.shared.setModuleEnabled(id: module.id, enabled: enabled)
        
        if enabled {
            module.start()
        } else {
            module.stop()
        }
    }
}
