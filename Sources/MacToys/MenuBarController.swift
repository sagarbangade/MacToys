import AppKit
import SwiftUI
import MacToysKit

@MainActor
class MenuBarController: NSObject {
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    
    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 400)
        popover.behavior = .transient
        
        super.init()
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "wrench.and.screwdriver", accessibilityDescription: "MacToys")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        
        let settingsView = SettingsWindow()
        popover.contentViewController = NSHostingController(rootView: settingsView)
    }
    
    @objc func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            closePopover(sender)
        } else {
            showPopover(sender)
        }
    }
    
    func showPopover(_ sender: AnyObject?) {
        if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    func closePopover(_ sender: AnyObject?) {
        popover.performClose(sender)
    }
}
