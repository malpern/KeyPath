import Foundation

class WizardLogger {
    static let shared = WizardLogger()

    private let logFileURL: URL
    private let dateFormatter: DateFormatter

    private init() {
        // Use the same logging directory as the main app
        let logsDir = URL(fileURLWithPath: "/Volumes/FlashGordon/Dropbox/code/KeyPath/logs")
        logFileURL = logsDir.appendingPathComponent("wizard-restart.log")

        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0) // UTC

        // Create logs directory if it doesn't exist
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
    }

    func log(_ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let logEntry = "[\(timestamp)] \(message)\n"

        // Print to console for immediate feedback
        print(logEntry.trimmingCharacters(in: .whitespacesAndNewlines))

        // Append to log file
        if let data = logEntry.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                // Append to existing file
                if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                // Create new file
                try? data.write(to: logFileURL)
            }
        }
    }
}
