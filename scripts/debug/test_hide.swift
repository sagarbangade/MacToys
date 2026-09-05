import AppKit

print("Starting app...")
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let target = NSWorkspace.shared.frontmostApplication
print("Target app was:", target?.localizedName ?? "none")

app.activate(ignoringOtherApps: true)
print("Activated ourself. Sleeping 1s...")
Thread.sleep(forTimeInterval: 1.0)

print("Hiding ourself...")
app.hide(nil)
if let target = target {
    print("Yielding to target...")
    if #available(macOS 14.0, *) {
        app.yieldActivation(to: target)
    }
    target.activate()
}

Thread.sleep(forTimeInterval: 0.5)
print("Frontmost app now:", NSWorkspace.shared.frontmostApplication?.localizedName ?? "none")
