import Foundation
import Cocoa
@preconcurrency import ApplicationServices

@MainActor
public final class PermissionManager: ObservableObject {
    public static let shared = PermissionManager()
    
    @Published public private(set) var hasScreenRecordingPermission = false
    @Published public private(set) var hasAccessibilityPermission = false
    
    private var monitoringTimer: Timer?
    
    private init() {
        checkPermissions()
    }
    
    public func checkPermissions() {
        hasAccessibilityPermission = AXIsProcessTrusted()
        hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()
    }
    
    public func requestScreenRecordingPermission() {
        CGRequestScreenCaptureAccess()
        checkPermissions()
    }
    
    nonisolated public func requestAccessibilityPermission() {
        // Use raw string to bypass C var concurrency check in Swift 6
        let options = ["AXTrustedCheckOptionPrompt": true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
        Task { @MainActor in
            self.checkPermissions()
        }
    }
    
    public func startMonitoringAccessibility() {
        monitoringTimer?.invalidate()
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                let wasGranted = self.hasAccessibilityPermission
                self.checkPermissions()
                
                if !wasGranted && self.hasAccessibilityPermission {
                    self.stopMonitoringAccessibility()
                    NotificationCenter.default.post(name: .accessibilityPermissionGranted, object: nil)
                }
            }
        }
    }
    
    public func stopMonitoringAccessibility() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
    }
}

extension Notification.Name {
    public static let accessibilityPermissionGranted = Notification.Name("accessibilityPermissionGranted")
}
