import AppKit

if let front = NSWorkspace.shared.frontmostApplication {
    print("Frontmost app:", front.localizedName ?? "unknown", front.bundleIdentifier ?? "unknown")
}
