import Foundation

@MainActor
public class ClipboardStore: ObservableObject {
    public static let shared = ClipboardStore()
    
    @Published public var items: [ClipboardItem] = []
    
    private let maxItems = 1000
    private let storageURL: URL
    private let imagesFolderURL: URL
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let mactoysDir = appSupport.appendingPathComponent("MacToys")
        storageURL = mactoysDir.appendingPathComponent("clipboard.json")
        imagesFolderURL = mactoysDir.appendingPathComponent("ClipboardImages")
        
        try? FileManager.default.createDirectory(at: imagesFolderURL, withIntermediateDirectories: true)
        load()
    }
    
    public func add(_ item: ClipboardItem) {
        // Remove existing item with same content if it exists
        if let existingIndex = items.firstIndex(where: { $0.content == item.content }) {
            let existing = items.remove(at: existingIndex)
            // Preserve the pin state, firstCopied, and increment timesCopied
            let newItem = ClipboardItem(
                id: existing.id,
                type: item.type,
                content: item.content,
                timestamp: item.timestamp,
                firstCopied: existing.firstCopied,
                timesCopied: existing.timesCopied + 1,
                isPinned: existing.isPinned,
                sourceApp: item.sourceApp ?? existing.sourceApp,
                sourceAppBundleID: item.sourceAppBundleID ?? existing.sourceAppBundleID
            )
            items.insert(newItem, at: 0)
        } else {
            items.insert(item, at: 0)
        }
        
        if items.count > maxItems {
            let removed = items.removeLast()
            if removed.type == .image {
                let fileURL = URL(fileURLWithPath: removed.content)
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        
        save()
    }
    
    public func togglePin(for id: UUID) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].isPinned.toggle()
            save()
        }
    }
    
    public func delete(id: UUID) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            let removed = items.remove(at: index)
            if removed.type == .image {
                let fileURL = URL(fileURLWithPath: removed.content)
                try? FileManager.default.removeItem(at: fileURL)
            }
            save()
        }
    }
    
    public func saveImage(_ data: Data) -> String? {
        let filename = UUID().uuidString + ".png"
        let fileURL = imagesFolderURL.appendingPathComponent(filename)
        do {
            try data.write(to: fileURL)
            return fileURL.path
        } catch {
            return nil
        }
    }
    
    private func save() {
        // Quick async save to avoid blocking MainActor
        let itemsToSave = self.items
        let url = self.storageURL
        Task.detached(priority: .background) {
            if let data = try? JSONEncoder().encode(itemsToSave) {
                try? data.write(to: url)
            }
        }
    }
    
    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) else { return }
        self.items = decoded
    }
}
