# Creating a MacToys Extension

MacToys is built on a modular extension architecture. Each tool (Text Extractor, Color Picker, etc.) is a self-contained Swift module that conforms to the `UtilityModule` protocol.

## Quick Start

1. Create a new directory under `Sources/Extensions/YourTool/`
2. Create your module file implementing `UtilityModule`
3. Add your target to `Package.swift`
4. Register it in `AppDelegate.swift`

## The UtilityModule Protocol

Every extension must conform to this protocol (defined in `MacToysKit`):

```swift
@MainActor
public protocol UtilityModule: ObservableObject, Identifiable {
    var id: String { get }
    var displayName: String { get }
    var description: String { get }
    var iconSymbol: String { get }        // SF Symbol name

    var isEnabled: Bool { get set }
    var requiredPermissions: [PermissionRequirement] { get }
    var shortcutName: KeyboardShortcuts.Name? { get }

    func start()                          // Called when the module is enabled
    func stop()                           // Called when the module is disabled
    func makeSettingsView() -> AnyView    // Settings UI for Preferences window
    func triggerAction()                  // Called when the keyboard shortcut fires
}
```

## Example: Minimal Extension

```swift
import Foundation
import Cocoa
import SwiftUI
import MacToysKit
@preconcurrency import KeyboardShortcuts

public extension KeyboardShortcuts.Name {
    static let myTool = Self("myTool", default: .init(.t, modifiers: [.command, .shift]))
}

@MainActor
public final class MyToolModule: UtilityModule {
    public let id = "myTool"
    public let displayName = "My Tool"
    public let description = "Does something cool"
    public let iconSymbol = "wand.and.stars"

    public var isEnabled: Bool = false
    public let requiredPermissions: [PermissionRequirement] = []
    public var shortcutName: KeyboardShortcuts.Name? { .myTool }

    public init() {}

    public func triggerAction() {
        // Your tool's main action
    }

    public func start() {
        KeyboardShortcuts.onKeyDown(for: .myTool) { [weak self] in
            self?.triggerAction()
        }
    }

    public func stop() {
        KeyboardShortcuts.disable(.myTool)
    }

    public func makeSettingsView() -> AnyView {
        AnyView(Text("My Tool Settings"))
    }
}
```

## Package.swift Entry

```swift
.target(
    name: "MyTool",
    dependencies: ["MacToysKit"],
    path: "Sources/Extensions/MyTool"
),
```

And add `"MyTool"` to the `MacToys` executable target's dependencies array.

## Registration

In `Sources/MacToys/AppDelegate.swift`, add:

```swift
import MyTool
// ...
ModuleRegistry.shared.register(MyToolModule())
```

## Web Companion Apps

If your extension needs a web-based UI (e.g., the Mobile Scanner), create a new app under `WebApps/your-app/`. Use the Mobile Scanner as a reference implementation.
