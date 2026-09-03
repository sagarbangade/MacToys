import Foundation
import ServiceManagement

@MainActor
public final class LoginItemManager {
    public static let shared = LoginItemManager()
    
    private init() {}
    
    public var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
    
    public func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            print("Failed to update login item: \(error)")
        }
    }
}
