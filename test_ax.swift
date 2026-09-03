import AppKit
import ApplicationServices

let trusted = AXIsProcessTrusted()
print("AXIsProcessTrusted:", trusted)
