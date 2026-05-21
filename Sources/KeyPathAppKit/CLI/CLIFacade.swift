import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle

/// Public facade exposing KeyPathAppKit internals for the CLI binary.
/// This is the stable API boundary between the CLI and the app library.
///
/// Standalone facades:
/// - RulesFacade.swift — Custom rules CRUD
/// - SimulatorFacade.swift — Key simulation and validation
/// - CollectionsFacade.swift — Collections, export/import, layers
/// - SystemFacade.swift — Service lifecycle, status, installer
/// - ConfigFacade.swift — Config, apply, TCP
/// - CLIFacade+Packs.swift — Pack management (extension on CLIFacade)
public struct CLIFacade: Sendable {
    public init() {}
}

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

// MARK: - Pack CLI Types

public struct CLIPack: Codable, Sendable {
    public let id: String
    public let name: String
    public let version: String
    public let category: String
    public let tagline: String
    public let isInstalled: Bool
    public let installedAt: Date?
}

public struct CLIPackDetail: Codable, Sendable {
    public let id: String
    public let name: String
    public let version: String
    public let category: String
    public let tagline: String
    public let shortDescription: String
    public let longDescription: String
    public let author: String
    public let isInstalled: Bool
    public let installedAt: Date?
    public let visualOnly: Bool
    public let bindings: [CLIPackBinding]
    public let quickSettings: [CLIPackQuickSetting]
    public let dependencies: [CLIPackDep]
    public let quickSettingValues: [String: Int]

    public init(from pack: Pack, record: InstalledPackRecord?) {
        id = pack.id
        name = pack.name
        version = pack.version
        category = pack.category
        tagline = pack.tagline
        shortDescription = pack.shortDescription
        longDescription = pack.longDescription
        author = pack.author
        isInstalled = record != nil
        installedAt = record?.installedAt
        visualOnly = pack.visualOnly
        bindings = pack.bindings.map { CLIPackBinding(input: $0.input, output: $0.output, holdOutput: $0.holdOutput) }
        quickSettings = pack.quickSettings.map { CLIPackQuickSetting(from: $0) }
        dependencies = pack.dependencies.map { CLIPackDep(from: $0) }
        quickSettingValues = record?.quickSettingValues ?? [:]
    }
}

public struct CLIPackBinding: Codable, Sendable {
    public let input: String
    public let output: String
    public let holdOutput: String?
}

public struct CLIPackQuickSetting: Codable, Sendable {
    public let id: String
    public let label: String
    public let defaultValue: Int
    public let min: Int
    public let max: Int
    public let step: Int
    public let unitSuffix: String

    public init(from setting: PackQuickSetting) {
        id = setting.id
        label = setting.label
        switch setting.kind {
        case let .slider(defaultValue, min, max, step, unitSuffix):
            self.defaultValue = defaultValue
            self.min = min
            self.max = max
            self.step = step
            self.unitSuffix = unitSuffix
        }
    }
}

public struct CLIPackDep: Codable, Sendable {
    public let packID: String
    public let kind: String
    public let description: String?

    public init(from dep: PackDependency) {
        packID = dep.packID
        kind = dep.kind.rawValue
        description = dep.description
    }
}

public struct CLIPackInstallResult: Codable, Sendable {
    public let packID: String
    public let packName: String
    public let action: String
    public let warnings: [String]
    public let quickSettingValues: [String: Int]
}

public struct AmbiguousPackMatch: Error, CustomStringConvertible {
    public struct Match: Sendable {
        public let name: String
        public let id: String
    }

    public let query: String
    public let matches: [Match]
    public let hint: String

    public init(query: String, matches: [Match], hint: String = "Use the full name or ID to disambiguate.") {
        self.query = query
        self.matches = matches
        self.hint = hint
    }

    public var description: String {
        var lines = ["Found \(matches.count) packs matching \"\(query)\":"]
        for match in matches {
            lines.append("  - \(match.name) (id: \(match.id))")
        }
        lines.append(hint)
        return lines.joined(separator: "\n")
    }
}

public struct CLIPackNotFound: Error, CustomStringConvertible {
    public let query: String
    public var description: String { "No pack found matching \"\(query)\"" }
}

public struct CLIPackSettingError: Error, CustomStringConvertible {
    public let packName: String
    public let settingKey: String
    public let validKeys: [String]
    public var description: String {
        if validKeys.isEmpty {
            return "Pack '\(packName)' has no quick settings, but --setting \(settingKey) was provided"
        }
        return "Unknown setting '\(settingKey)' for pack '\(packName)'. Valid keys: \(validKeys.joined(separator: ", "))"
    }
}

public struct PackManagedCollectionError: Error, CustomStringConvertible {
    public let collectionName: String
    public let packName: String
    public let packID: String
    public var description: String {
        let slug = packName.lowercased().replacingOccurrences(of: " ", with: "-")
        return "'\(collectionName)' is managed by pack '\(packName)'. Run 'keypath pack uninstall \(slug)' to release it."
    }
}

// MARK: - Stderr Helper

public func printErr(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}
