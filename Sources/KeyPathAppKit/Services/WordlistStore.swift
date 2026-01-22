import Foundation

/// Loads autocomplete wordlists from user overrides or bundled resources.
public enum WordlistStore {
    public enum Source: String, Codable, Sendable {
        case bundle
        case user
    }

    public struct Descriptor: Codable, Equatable, Sendable {
        public var id: String
        public var source: Source
        public var version: String?

        public init(id: String, source: Source, version: String? = nil) {
            self.id = id
            self.source = source
            self.version = version
        }
    }

    public static let defaultWordlistId = "en_US"

    public static func loadWordlist(
        id: String = defaultWordlistId,
        appSupportURL: URL = defaultAppSupportURL(),
        bundle: Bundle = .module
    ) -> [String] {
        if let userURL = userWordlistURL(id: id, appSupportURL: appSupportURL),
           let contents = try? String(contentsOf: userURL)
        {
            return parse(contents: contents)
        }

        if let bundleURL = bundle.url(forResource: id, withExtension: "txt", subdirectory: "Wordlists"),
           let contents = try? String(contentsOf: bundleURL)
        {
            return parse(contents: contents)
        }

        return []
    }

    public static func userWordlistURL(id: String, appSupportURL: URL) -> URL? {
        appSupportURL
            .appendingPathComponent("wordlists", isDirectory: true)
            .appendingPathComponent("\(id).txt")
    }

    public static func parse(contents: String) -> [String] {
        contents
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    private static func defaultAppSupportURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return (base ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("KeyPath", isDirectory: true)
    }
}
