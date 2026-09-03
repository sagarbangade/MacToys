import AppKit

let pb = NSPasteboard.general
pb.clearContents()

let image = NSImage(size: NSSize(width: 100, height: 100))
image.lockFocus()
NSColor.red.set()
NSRect(x: 0, y: 0, width: 100, height: 100).fill()
image.unlockFocus()

pb.writeObjects([image])
print(pb.types ?? [])
