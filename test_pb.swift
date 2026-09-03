import AppKit
let pb = NSPasteboard.general
print(pb.types ?? [])
if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
    print("NSURLs:", urls)
} else {
    print("No NSURLs found")
}
