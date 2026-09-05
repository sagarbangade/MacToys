import AppKit
let pb = NSPasteboard.general
if let paths = pb.propertyList(forType: .init("NSFilenamesPboardType")) as? [String] {
    print("NSFilenames:", paths)
}
if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
    print("NSURLs:", urls)
}
