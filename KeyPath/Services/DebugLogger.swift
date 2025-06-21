import Foundation

class DebugLogger {
    static let shared = DebugLogger()
    private let debugPath = "/Users/malpern/Library/CloudStorage/Dropbox/code/KeyPath/debug.txt"
    
    private init() {}
    
    func log(_ message: String) {
        let timestamp = DateFormatter().string(from: Date())
        let logMessage = "\(timestamp): \(message)\n"
        
        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: debugPath) {
                let fileHandle = FileHandle(forWritingAtPath: debugPath)
                fileHandle?.seekToEndOfFile()
                fileHandle?.write(data)
                fileHandle?.closeFile()
            } else {
                try? data.write(to: URL(fileURLWithPath: debugPath))
            }
        }
    }
}
