import Foundation
extension String {
    func appendLine(to path: String) {
        if let data = (self).data(using: .utf8) {
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
"test\n".appendLine(to: "/tmp/test.log")
