import Foundation
import AppKit

@MainActor
public class ClipboardWatcher {
    private var lastChangeCount: Int = 0
    private var isWatching = false
    private var task: Task<Void, Never>?
    
    public init() {}
    
    public func start() {
        guard !isWatching else { return }
        isWatching = true
        lastChangeCount = NSPasteboard.general.changeCount
        
        task = Task {
            while !Task.isCancelled {
                checkPasteboard()
                try? await Task.sleep(nanoseconds: 750_000_000) // 0.75s
            }
        }
    }
    
    public func stop() {
        isWatching = false
        task?.cancel()
        task = nil
    }
    
    private func checkPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        
        // Capture source app
        let frontApp = NSWorkspace.shared.frontmostApplication
        let appName = frontApp?.localizedName
        let appBundleID = frontApp?.bundleIdentifier
        
        // Priority 1: Files
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            let paths = urls.map { $0.path }.joined(separator: "\n")
            let item = ClipboardItem(type: .file, content: paths, sourceApp: appName, sourceAppBundleID: appBundleID)
            ClipboardStore.shared.add(item)
            return
        }
        
        // Priority 2: Links
        if let string = pb.string(forType: .URL) ?? pb.string(forType: .string),
           string.hasPrefix("http://") || string.hasPrefix("https://"),
           URL(string: string) != nil {
            let item = ClipboardItem(type: .link, content: string, sourceApp: appName, sourceAppBundleID: appBundleID)
            ClipboardStore.shared.add(item)
            return
        }
        
        // Priority 3: Text
        if let string = pb.string(forType: .string) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let item = ClipboardItem(type: .text, content: string, sourceApp: appName, sourceAppBundleID: appBundleID)
                ClipboardStore.shared.add(item)
            }
            return
        }
        
        // Priority 4: Images
        if let imgData = pb.data(forType: .png) ?? pb.data(forType: .tiff) {
            var finalData = imgData
            if let image = NSImage(data: imgData),
               let tiff = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let png = bitmap.representation(using: .png, properties: [:]) {
                finalData = png
            }
            
            if let path = ClipboardStore.shared.saveImage(finalData) {
                let item = ClipboardItem(type: .image, content: path, sourceApp: appName, sourceAppBundleID: appBundleID)
                ClipboardStore.shared.add(item)
            }
            return
        }
    }
}
