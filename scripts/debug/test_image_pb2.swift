import AppKit

let pb = NSPasteboard.general
pb.clearContents()

let data = "fake png data".data(using: .utf8)!
let fileURL = URL(fileURLWithPath: "/tmp/fake.png")
try? data.write(to: fileURL)

// Write both raw PNG and file URL
pb.declareTypes([.png, .fileURL], owner: nil)
pb.setData(data, forType: .png)
pb.setString(fileURL.absoluteString, forType: .fileURL)

print(pb.types ?? [])
