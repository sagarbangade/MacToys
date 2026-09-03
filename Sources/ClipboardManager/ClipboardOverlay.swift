import SwiftUI
import AppKit

@MainActor
extension Notification.Name {
    static let clipboardKeyEvent = Notification.Name("clipboardKeyEvent")
}

extension String {
    func appendLine(to path: String) {
        if let data = self.data(using: .utf8) {
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
    }
}

public class ClipboardOverlayWindow: NSPanel {
    public override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            let keys: [UInt16] = [125, 126, 36, 76, 53] // Down, Up, Return, Enter, Esc
            let isCmd = event.modifierFlags.contains(.command)
            let isCmdP = isCmd && event.keyCode == 35
            let isCmdDel = isCmd && event.keyCode == 51
            
            if keys.contains(event.keyCode) || isCmdP || isCmdDel {
                "[\(Date())] sendEvent intercepted key: \(event.keyCode)\n".appendLine(to: "/tmp/mactoys.log")
                NotificationCenter.default.post(name: .clipboardKeyEvent, object: event)
                return // Swallow the event completely!
            }
        }
        super.sendEvent(event)
    }

    public init() {
        let screenRect = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let w: CGFloat = 800
        let h: CGFloat = 500
        let rect = NSRect(
            x: (screenRect.width - w) / 2 + screenRect.minX,
            y: (screenRect.height - h) / 2 + screenRect.minY,
            width: w,
            height: h
        )
        
        super.init(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = false
        
        // Add frosted glass
        let visualEffect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        visualEffect.material = .popover
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        
        let hostingView = NSHostingView(rootView: ClipboardView(window: self))
        hostingView.frame = visualEffect.bounds
        visualEffect.addSubview(hostingView)
        hostingView.autoresizingMask = [.width, .height]
        
        // Round corners
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.borderColor = NSColor.separatorColor.cgColor
        visualEffect.layer?.borderWidth = 1
        
        self.contentView = visualEffect
        
        // Close window when user clicks completely outside
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: self, queue: .main) { [weak self] _ in
            self?.orderOut(nil)
        }
    }
    
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }
}

struct ClipboardView: View {
    weak var window: NSPanel?
    @ObservedObject var store = ClipboardStore.shared
    @ObservedObject var targetTracker = TargetAppTracker.shared
    @State private var searchText = ""
    @State private var selectedIndex: Int = 0
    @State private var selectedFilterType: ClipboardItemType? = nil
    @State private var showTypeFilter = false
    
    var filteredItems: [ClipboardItem] {
        let pinned = store.items.filter { $0.isPinned }
        let unpinned = store.items.filter { !$0.isPinned }
        var all = pinned + unpinned
        
        if let type = selectedFilterType {
            all = all.filter { $0.type == type }
        }
        
        if searchText.isEmpty {
            return all
        } else {
            return all.filter { $0.content.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var selectedItem: ClipboardItem? {
        guard selectedIndex >= 0 && selectedIndex < filteredItems.count else { return nil }
        return filteredItems[selectedIndex]
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Search Bar (Raycast Style)
            HStack(spacing: 12) {
                Button(action: {
                    window?.orderOut(nil)
                }) {
                    Image(systemName: "arrow.left")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14, weight: .semibold))
                        .padding(6)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                
                TextField("Type to filter entries...", text: $searchText)
                    .font(.system(size: 18, weight: .regular))
                    .textFieldStyle(PlainTextFieldStyle())
                    .onChange(of: searchText) { oldValue, newValue in
                        selectedIndex = 0
                    }
                
                Spacer()
                
                // Custom Popover Dropdown Filter
                Button(action: { showTypeFilter.toggle() }) {
                    HStack {
                        Text(filterLabelText())
                        Image(systemName: showTypeFilter ? "chevron.up" : "chevron.down")
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .popover(isPresented: $showTypeFilter, arrowEdge: .bottom) {
                    TypeFilterPopover(selectedFilterType: $selectedFilterType, isPresented: $showTypeFilter, selectedIndex: $selectedIndex)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(WindowDragView())
            
            Divider()
            
            // Main Two-Column Content
            HStack(spacing: 0) {
                // Left Column: List
                VStack(spacing: 0) {
                    if filteredItems.isEmpty {
                        Spacer()
                        Text("No entries found")
                            .foregroundColor(.secondary)
                        Spacer()
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 2) {
                                    ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                                        ClipboardRow(item: item, isSelected: index == selectedIndex)
                                            .id(index)
                                            .onTapGesture {
                                                selectedIndex = index
                                            }
                                            .simultaneousGesture(TapGesture(count: 2).onEnded {
                                                pasteItem(item)
                                            })
                                    }
                                }
                                .padding(8)
                            }
                            .onChange(of: selectedIndex) { oldIndex, newIndex in
                                withAnimation(.easeInOut(duration: 0.1)) {
                                    proxy.scrollTo(newIndex, anchor: .center)
                                }
                            }
                        }
                    }
                }
                .frame(width: 300)
                
                Divider()
                
                // Right Column: Detail Preview
                VStack {
                    if let item = selectedItem {
                        ClipboardDetailView(item: item)
                    } else {
                        Spacer()
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.3))
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.4))
            }
            
            Divider()
            
            // Footer
            HStack {
                Image(systemName: "doc.on.clipboard.fill")
                    .foregroundColor(.accentColor)
                Text("Clipboard History")
                    .font(.system(size: 12, weight: .medium))
                
                Spacer()
                
                Text("Pin Item")
                    .font(.system(size: 12, weight: .medium))
                HStack(spacing: 2) {
                    Image(systemName: "command")
                    Text("P")
                }
                .font(.system(size: 10, weight: .bold))
                .padding(4)
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(4)
                
                Text("|")
                    .foregroundColor(.secondary.opacity(0.5))
                    .padding(.horizontal, 4)
                
                Text("Paste to \(targetTracker.targetAppName)")
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .bold))
                    .padding(4)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipboardKeyEvent)) { notification in
            guard let event = notification.object as? NSEvent else { return }
            
            if event.keyCode == 53 { // Escape
                window?.orderOut(nil)
                return
            }
            
            let count = filteredItems.count
            guard count > 0 else { return }
            
            if event.modifierFlags.contains(.command) && event.keyCode == 35 { // Cmd+P
                if selectedIndex >= 0 && selectedIndex < count {
                    store.togglePin(for: filteredItems[selectedIndex].id)
                }
                return
            }
            
            if event.modifierFlags.contains(.command) && event.keyCode == 51 { // Cmd+Delete
                if selectedIndex >= 0 && selectedIndex < count {
                    store.delete(id: filteredItems[selectedIndex].id)
                    if selectedIndex >= filteredItems.count {
                        selectedIndex = max(0, filteredItems.count - 1)
                    }
                }
                return
            }
            
            switch event.keyCode {
            case 125: // Down Arrow
                if selectedIndex < count - 1 { selectedIndex += 1 }
            case 126: // Up Arrow
                if selectedIndex > 0 { selectedIndex -= 1 }
            case 36, 76: // Return or Enter
                "[\(Date())] onReceive got Return/Enter, selectedIndex: \(selectedIndex), count: \(count)\n".appendLine(to: "/tmp/mactoys.log")
                if selectedIndex >= 0 && selectedIndex < count {
                    pasteItem(filteredItems[selectedIndex])
                }
            default:
                break
            }
        }
    }
    
    private func filterLabelText() -> String {
        guard let type = selectedFilterType else { return "All Types" }
        switch type {
        case .text: return "Text Only"
        case .image: return "Images Only"
        case .file: return "Files Only"
        case .link: return "Links Only"
        }
    }
    
    private func pasteItem(_ item: ClipboardItem) {
        let logMsg = "[\(Date())] pasteItem called for: \(item.type), AXIsProcessTrusted: \(AXIsProcessTrusted()), targetApp: \(TargetAppTracker.shared.targetApp?.localizedName ?? "nil")\n"
        try? logMsg.appendLine(to: "/tmp/mactoys.log")
        
        window?.orderOut(nil)
        NSApp.hide(nil)
        
        if let app = TargetAppTracker.shared.targetApp {
            if #available(macOS 14.0, *) {
                NSApp.yieldActivation(to: app)
            }
            app.activate()
        }
        
        let pb = NSPasteboard.general
        pb.clearContents()
        
        switch item.type {
        case .text:
            pb.setString(item.content, forType: .string)
        case .link:
            pb.setString(item.content, forType: .URL)
            pb.setString(item.content, forType: .string)
        case .file:
            let paths = item.content.components(separatedBy: "\n")
            let urls = paths.map { URL(fileURLWithPath: $0) as NSURL }
            pb.writeObjects(urls)
        case .image:
            let fileURL = URL(fileURLWithPath: item.content)
            if let data = try? Data(contentsOf: fileURL) {
                pb.declareTypes([.png, .fileURL], owner: nil)
                pb.setData(data, forType: .png)
                pb.setString(fileURL.absoluteString, forType: .fileURL)
            }
        }
        
        // Wait for the previous app to regain focus before simulating Cmd+V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            simulatePaste()
        }
    }
    
    private func simulatePaste() {
        let isTrusted = AXIsProcessTrusted()
        let logMsg = "[\(Date())] simulatePaste called, isTrusted: \(isTrusted)\n"
        logMsg.appendLine(to: "/tmp/mactoys.log")
        
        guard isTrusted else {
            let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
            
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Accessibility Permission Required"
                alert.informativeText = "MacToys needs Accessibility permission to automatically paste into other applications.\n\nPlease enable MacToys in System Settings > Privacy & Security > Accessibility."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "Cancel")
                
                if alert.runModal() == .alertFirstButtonReturn {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            return
        }
        
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents], state: .eventSuppressionStateSuppressionInterval)
        
        let vKeyCode: CGKeyCode = 9
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        keyUp?.flags = .maskCommand
        
        keyDown?.post(tap: .cgAnnotatedSessionEventTap)
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)
    }
}

struct TypeFilterPopover: View {
    @Binding var selectedFilterType: ClipboardItemType?
    @Binding var isPresented: Bool
    @Binding var selectedIndex: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FilterRow(title: "All Types", isSelected: selectedFilterType == nil) {
                selectedFilterType = nil
                close()
            }
            Divider().padding(.vertical, 4)
            FilterRow(title: "Text Only", isSelected: selectedFilterType == .text) {
                selectedFilterType = .text
                close()
            }
            FilterRow(title: "Images Only", isSelected: selectedFilterType == .image) {
                selectedFilterType = .image
                close()
            }
            FilterRow(title: "Files Only", isSelected: selectedFilterType == .file) {
                selectedFilterType = .file
                close()
            }
            FilterRow(title: "Links Only", isSelected: selectedFilterType == .link) {
                selectedFilterType = .link
                close()
            }
        }
        .padding(8)
        .frame(width: 180)
    }
    
    private func close() {
        selectedIndex = 0
        isPresented = false
    }
}

struct FilterRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? .primary : .secondary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.primary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle()) // Fix empty space clicking
            .background(isHovered ? Color.primary.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { isHovered = $0 }
    }
}

struct ClipboardRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            if item.type == .file, let firstPath = item.content.components(separatedBy: "\n").first {
                Image(nsImage: IconCache.shared.fileIcon(path: firstPath))
                    .resizable()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: iconForType(item.type))
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .frame(width: 16)
            }
            
            if item.type == .image {
                Text("Image")
                    .lineLimit(1)
                    .font(.system(size: 13))
            } else if item.type == .file {
                Text(URL(fileURLWithPath: item.content.components(separatedBy: "\n").first ?? "").lastPathComponent)
                    .lineLimit(1)
                    .font(.system(size: 13))
            } else {
                Text(item.content.replacingOccurrences(of: "\n", with: " "))
                    .lineLimit(1)
                    .font(.system(size: 13))
            }
            
            Spacer()
            
            if let bundleID = item.sourceAppBundleID,
               let icon = IconCache.shared.appIcon(bundleID: bundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 14, height: 14)
                    .opacity(isSelected ? 1.0 : 0.6)
            }
            
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .font(.system(size: 10))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle()) // Ensures the entire row, including empty space, is clickable!
        .background(isSelected ? Color.primary.opacity(0.1) : Color.clear)
        .foregroundColor(.primary)
        .cornerRadius(6)
    }
    
    private func iconForType(_ type: ClipboardItemType) -> String {
        switch type {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .file: return "doc"
        case .image: return "photo"
        }
    }
}

struct ClipboardDetailView: View {
    let item: ClipboardItem
    
    var body: some View {
        VStack(spacing: 0) {
            // Main Preview Area
            VStack {
                Spacer()
                if item.type == .text || item.type == .link {
                    ScrollView {
                        Text(item.content.count > 10000 ? String(item.content.prefix(10000)) + "\n\n... (content truncated for preview)" : item.content)
                            .font(.system(size: 14))
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)
                            .textSelection(.enabled)
                    }
                } else if item.type == .image {
                    if let img = NSImage(contentsOfFile: item.content) {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding()
                    } else {
                        Text("Image not found")
                            .foregroundColor(.secondary)
                    }
                } else if item.type == .file {
                    if let firstPath = item.content.components(separatedBy: "\n").first {
                        Image(nsImage: IconCache.shared.fileIcon(path: firstPath))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 64, height: 64)
                            .padding(.top, 40)
                    } else {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.secondary)
                            .padding(.top, 40)
                    }
                    Text(URL(fileURLWithPath: item.content.components(separatedBy: "\n").first ?? "").lastPathComponent)
                        .font(.headline)
                        .padding(.top, 8)
                }
                Spacer()
            }
            .frame(maxHeight: .infinity)
            
            Divider()
            
            // Metadata Grid
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Information")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Text("Source")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                        
                        if let bundleID = item.sourceAppBundleID,
                           let icon = IconCache.shared.appIcon(bundleID: bundleID) {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 14, height: 14)
                        }
                        
                        Text(item.sourceApp ?? "System")
                            .font(.system(size: 12, weight: .medium))
                    }
                    
                    HStack {
                        Text("Content type")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(item.type.rawValue.capitalized)
                            .font(.system(size: 12, weight: .medium))
                    }
                    
                    if item.type == .text {
                        HStack {
                            Text("Characters")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(item.content.count)")
                                .font(.system(size: 12, weight: .medium))
                        }
                        
                        HStack {
                            Text("Words")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            let words = item.content.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
                            Text("\(words)")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    
                    if item.type == .image, let img = NSImage(contentsOfFile: item.content) {
                        HStack {
                            Text("Dimensions")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(img.size.width)) × \(Int(img.size.height))")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    
                    if item.type == .file {
                        let path = item.content.components(separatedBy: "\n").first ?? ""
                        HStack {
                            Text("Path")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(shortPath(path))
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        
                        HStack {
                            Text("File size")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(fileSize(path))
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    
                    HStack {
                        Text("Times copied")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(item.timesCopied)")
                            .font(.system(size: 12, weight: .medium))
                    }
                    
                    HStack {
                        Text("Last copied")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(timeDisplay(item.timestamp))
                            .font(.system(size: 12, weight: .medium))
                    }
                    
                    HStack {
                        Text("First copied")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(timeDisplay(item.firstCopied))
                            .font(.system(size: 12, weight: .medium))
                    }
                    
                    Divider()
                    
                    // Visible Pin Button
                    Button(action: {
                        ClipboardStore.shared.togglePin(for: item.id)
                    }) {
                        HStack {
                            Spacer()
                            Image(systemName: item.isPinned ? "pin.slash.fill" : "pin.fill")
                            Text(item.isPinned ? "Unpin Item" : "Pin to Top")
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(16)
            }
            .textSelection(.enabled)
            .frame(maxHeight: 140) // Restricts metadata to ~30% of the window
            .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
        }
    }
    
    private func timeDisplay(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "'Today at' h:mm:ss a"
        } else if calendar.isDateInYesterday(date) {
            formatter.dateFormat = "'Yesterday at' h:mm:ss a"
        } else {
            formatter.dateFormat = "d MMM yyyy 'at' h:mm:ss a"
        }
        return formatter.string(from: date)
    }
    
    private func shortPath(_ path: String) -> String {
        let nsPath = path as NSString
        let homeDir = NSHomeDirectory() as NSString
        if nsPath.hasPrefix(homeDir as String) {
            return "~/" + nsPath.substring(from: homeDir.length).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return path
    }
    
    private func fileSize(_ path: String) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64 else {
            return "Unknown"
        }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

final class IconCache: @unchecked Sendable {
    static let shared = IconCache()
    private var cache: [String: NSImage] = [:]
    private let queue = DispatchQueue(label: "com.mactoys.iconcache")
    
    func appIcon(bundleID: String) -> NSImage? {
        queue.sync {
            if let cached = cache[bundleID] { return cached }
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                cache[bundleID] = icon
                return icon
            }
            return nil
        }
    }
    
    func fileIcon(path: String) -> NSImage {
        queue.sync {
            if let cached = cache[path] { return cached }
            let icon = NSWorkspace.shared.icon(forFile: path)
            cache[path] = icon
            return icon
        }
    }
}

struct WindowDragView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        return DraggingView()
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

class DraggingView: NSView {
    override var acceptsFirstResponder: Bool { false }
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
