import Foundation

// MARK: - Version

public enum CLIVersion {
    public static let current: String = {
        let candidates = [
            "/Applications/KeyPath.app",
            NSString("~/Applications/KeyPath.app").expandingTildeInPath,
        ]
        for path in candidates {
            if let bundle = Bundle(path: path),
               let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String
            {
                return version
            }
        }
        return "1.0.0"
    }()
}

// MARK: - Stderr Helper

public func printErr(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}
