import Foundation

/// Represents a simple A→B key mapping
public struct SimpleMapping: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let fromKey: String
    public let toKey: String
    public var enabled: Bool
    public let filePath: String
    public let lineRange: ClosedRange<Int>?
    public let checksum: String?

    public init(
        id: UUID = UUID(),
        fromKey: String,
        toKey: String,
        enabled: Bool = true,
        filePath: String,
        lineRange: ClosedRange<Int>? = nil,
        checksum: String? = nil
    ) {
        self.id = id
        self.fromKey = fromKey
        self.toKey = toKey
        self.enabled = enabled
        self.filePath = filePath
        self.lineRange = lineRange
        self.checksum = checksum
    }

    public func validationErrors(existing: [SimpleMapping] = [])
        -> [CustomRuleValidator.ValidationError]
    {
        var errors = CustomRuleValidator.validateKeys(input: fromKey, output: toKey)

        // Conflict: same input already mapped to different output
        let normalizedInput = CustomRuleValidator.normalizeKey(fromKey)
        if let conflict = existing.first(
            where: { $0.id != id && CustomRuleValidator.normalizeKey($0.fromKey) == normalizedInput }
        ) {
            errors.append(.conflict(with: conflict.toKey, key: normalizedInput))
        }

        return errors
    }
}

/// Preset mapping definition for the catalog
public struct SimpleModPreset: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let description: String
    public let category: String
    public let fromKey: String
    public let toKey: String

    public init(
        id: UUID = UUID(),
        name: String,
        description: String,
        category: String,
        fromKey: String,
        toKey: String
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.fromKey = fromKey
        self.toKey = toKey
    }

    public func validationErrors() -> [CustomRuleValidator.ValidationError] {
        CustomRuleValidator.validateKeys(input: fromKey, output: toKey)
    }
}

/// Conflict information for a mapping
public struct MappingConflict: Sendable {
    public let fromKey: String
    public let conflictingLine: Int
    public let conflictingFile: String
    public let reason: String

    public init(fromKey: String, conflictingLine: Int, conflictingFile: String, reason: String) {
        self.fromKey = fromKey
        self.conflictingLine = conflictingLine
        self.conflictingFile = conflictingFile
        self.reason = reason
    }
}

/// Parsed sentinel block information
public struct SentinelBlock: Sendable {
    public let id: String
    public let version: Int
    public let startLine: Int
    public let endLine: Int
    public let mappings: [SimpleMapping]

    public init(id: String, version: Int, startLine: Int, endLine: Int, mappings: [SimpleMapping]) {
        self.id = id
        self.version = version
        self.startLine = startLine
        self.endLine = endLine
        self.mappings = mappings
    }
}
