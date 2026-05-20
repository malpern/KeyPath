import ArgumentParser
import Foundation

public struct CLIError: Error, Codable, Sendable {
    public let code: CLIExitCode
    public let message: String
    public let hint: String?
    public let details: [String]?
    public let docsUrl: String?

    public init(code: CLIExitCode, message: String, hint: String?, details: [String]?, docsUrl: String?) {
        self.code = code
        self.message = message
        self.hint = hint
        self.details = details
        self.docsUrl = docsUrl
    }
}

public enum CLIExitCode: Int32, Codable, Sendable, CaseIterable {
    case success = 0
    case usage = 2
    case validation = 3
    case conflict = 4
    case notFound = 5
    case serviceUnreachable = 6
    case permissionBlocked = 7
    case kanataInvalid = 8
}

extension CLIExitCode {
    var exitCode: ExitCode {
        ExitCode(rawValue: rawValue)
    }
}

// MARK: - Documentation URLs

public enum CLIDocsURL {
    static let faq = "https://github.com/malpern/KeyPath/blob/master/docs/FAQ.md"
    static let debugging = "https://github.com/malpern/KeyPath/blob/master/docs/DEBUGGING_KANATA.md"
    static let actionURI = "https://github.com/malpern/KeyPath/blob/master/docs/ACTION_URI_SYSTEM.md"
    static let ruleCollections = "https://github.com/malpern/KeyPath/blob/master/docs/architecture/rules-architecture.html"
    static let permissions = "https://github.com/malpern/KeyPath/blob/master/docs/architecture/permissions-architecture.html"
}

// MARK: - Factory Methods

public extension CLIError {
    static func notFound(_ entity: String, query: String, listCommand: String, suggestions: [String] = []) -> CLIError {
        var hint = "Run '\(listCommand)' to see available \(entity.lowercased())s"
        if !suggestions.isEmpty {
            hint = "Did you mean: \(suggestions.joined(separator: ", "))?\n" + hint
        }
        return CLIError(
            code: .notFound,
            message: "\(entity) not found: '\(query)'",
            hint: hint,
            details: ["query: '\(query)'"],
            docsUrl: nil
        )
    }

    static func serviceUnreachable(hint: String = "Run 'keypath service status --json' to check if Kanata is running") -> CLIError {
        CLIError(
            code: .serviceUnreachable,
            message: "Could not connect to Kanata TCP server",
            hint: hint,
            details: nil,
            docsUrl: CLIDocsURL.debugging
        )
    }

    static func validation(_ message: String, hint: String? = nil, details: [String]? = nil) -> CLIError {
        CLIError(
            code: .validation,
            message: message,
            hint: hint,
            details: details,
            docsUrl: nil
        )
    }

    static func conflict(_ message: String, hint: String? = nil) -> CLIError {
        CLIError(
            code: .conflict,
            message: message,
            hint: hint,
            details: nil,
            docsUrl: nil
        )
    }

    static func invalidKey(_ key: String, label: String) -> CLIError {
        CLIError(
            code: .validation,
            message: "Invalid \(label) key: '\(key)'",
            hint: "Run 'keypath help-topics schemas rule' for valid key names (e.g., caps, lalt, esc, lctl, spc, ret)",
            details: nil,
            docsUrl: CLIDocsURL.faq
        )
    }

    static func ambiguous(_ message: String, matches: [String]) -> CLIError {
        CLIError(
            code: .conflict,
            message: message,
            hint: "Use the full name or ID to disambiguate",
            details: matches,
            docsUrl: nil
        )
    }

    static func kanataInvalid(errors: [String]) -> CLIError {
        CLIError(
            code: .kanataInvalid,
            message: "Configuration validation failed",
            hint: "Fix the errors above, then run 'keypath config check --json'",
            details: errors,
            docsUrl: CLIDocsURL.debugging
        )
    }
}
