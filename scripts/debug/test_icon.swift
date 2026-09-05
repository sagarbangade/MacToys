import AppKit
print("Getting icon for empty string...")
let icon = NSWorkspace.shared.icon(forFile: "")
print("Icon:", icon)
