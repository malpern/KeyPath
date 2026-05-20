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

    static func serviceUnreachable(hint: String = "Is Kanata running? Check with 'keypath service status'") -> CLIError {
        CLIError(
            code: .serviceUnreachable,
            message: "Could not connect to Kanata TCP server",
            hint: hint,
            details: nil,
            docsUrl: nil
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
            hint: "Use canonical Kanata key names (e.g., caps, lalt, esc, lctl, spc, ret)",
            details: nil,
            docsUrl: nil
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
            hint: "Fix the errors above and run 'keypath config check' again",
            details: errors,
            docsUrl: nil
        )
    }
}
