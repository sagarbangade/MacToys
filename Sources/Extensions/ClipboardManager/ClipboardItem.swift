import Foundation
import AppKit

public enum ClipboardItemType: String, Codable, Sendable {
    case text
    case link
    case file
    case image
}

public struct ClipboardItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let type: ClipboardItemType
    public let content: String // text, url, file path, or image path
    public let timestamp: Date // Last copied time
    public let firstCopied: Date
    public var timesCopied: Int
    public var isPinned: Bool
    
    // New Source Metadata
    public let sourceApp: String?
    public let sourceAppBundleID: String?
    
    public init(id: UUID = UUID(), type: ClipboardItemType, content: String, timestamp: Date = Date(), firstCopied: Date? = nil, timesCopied: Int = 1, isPinned: Bool = false, sourceApp: String? = nil, sourceAppBundleID: String? = nil) {
        self.id = id
        self.type = type
        self.content = content
        self.timestamp = timestamp
        self.firstCopied = firstCopied ?? timestamp
        self.timesCopied = timesCopied
        self.isPinned = isPinned
        self.sourceApp = sourceApp
        self.sourceAppBundleID = sourceAppBundleID
    }
}
