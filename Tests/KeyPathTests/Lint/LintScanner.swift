import Foundation

enum LintScanner {
    enum Error: Swift.Error, CustomStringConvertible {
        case couldNotEnumerate(String)
        case missingFunction(String, String)
        case missingFunctionBrace(String, String)
        case unterminatedFunction(String, String)

        var description: String {
            switch self {
            case let .couldNotEnumerate(path):
                "Could not enumerate \(path)"
            case let .missingFunction(name, path):
                "Could not find func \(name) in \(path)"
            case let .missingFunctionBrace(name, path):
                "Could not find opening brace for func \(name) in \(path)"
            case let .unterminatedFunction(name, path):
                "Could not find closing brace for func \(name) in \(path)"
            }
        }
    }

    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Lint
            .deletingLastPathComponent() // KeyPathTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
    }

    static func path(_ relativePath: String) -> URL {
        repositoryRoot.appendingPathComponent(relativePath)
    }

    static func relativePath(_ fileURL: URL) -> String {
        fileURL.path.replacingOccurrences(of: repositoryRoot.path + "/", with: "")
    }

    static func swiftFiles(under root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            throw Error.couldNotEnumerate(root.path)
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "swift" else { return nil }
            return url
        }
    }

    static func matchingLines(
        under root: URL,
        patterns: [String],
        allowList: Set<String> = [],
        allowFileNames: Set<String> = []
    ) throws -> [String] {
        try swiftFiles(under: root).flatMap { fileURL -> [String] in
            if allowList.contains(relativePath(fileURL)) { return [] }
            if allowFileNames.contains(fileURL.lastPathComponent) { return [] }
            return try matchingLines(in: fileURL, patterns: patterns)
        }
    }

    static func matchingLines(in fileURL: URL, patterns: [String]) throws -> [String] {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let regexes = try patterns.map { try NSRegularExpression(pattern: $0) }
        let relativePath = relativePath(fileURL)

        return contents.components(separatedBy: .newlines).enumerated().compactMap { lineNumber, rawLine in
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !isIgnoredLine(trimmed) else { return nil }

            let range = NSRange(rawLine.startIndex..., in: rawLine)
            guard regexes.contains(where: { $0.firstMatch(in: rawLine, range: range) != nil }) else {
                return nil
            }
            return "\(relativePath):\(lineNumber + 1): \(trimmed)"
        }
    }

    static func functionBody(named functionName: String, in fileURL: URL) throws -> String {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        guard let nameRange = contents.range(of: "func \(functionName)") else {
            throw Error.missingFunction(functionName, relativePath(fileURL))
        }
        guard let openBrace = contents[nameRange.lowerBound...].firstIndex(of: "{") else {
            throw Error.missingFunctionBrace(functionName, relativePath(fileURL))
        }

        var depth = 0
        var cursor = openBrace
        while cursor < contents.endIndex {
            let char = contents[cursor]
            if char == "{" {
                depth += 1
            } else if char == "}" {
                depth -= 1
                if depth == 0 {
                    let bodyStart = contents.index(after: openBrace)
                    return String(contents[bodyStart ..< cursor])
                }
            }
            cursor = contents.index(after: cursor)
        }

        throw Error.unterminatedFunction(functionName, relativePath(fileURL))
    }

    private static func isIgnoredLine(_ trimmed: String) -> Bool {
        trimmed.isEmpty ||
            trimmed.hasPrefix("//") ||
            trimmed.hasPrefix("///") ||
            trimmed.hasPrefix("*")
    }
}
