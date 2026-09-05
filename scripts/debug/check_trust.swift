import Foundation
import ApplicationServices

let isTrusted = AXIsProcessTrusted()
print("Process trusted:", isTrusted)

let opts = ["AXTrustedCheckOptionPrompt": false] as CFDictionary
print("Trusted with opts:", AXIsProcessTrustedWithOptions(opts))
