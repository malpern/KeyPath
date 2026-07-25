//
//  SequencesConfig.swift
//  KeyPath
//
//  Created by Claude Code on 2026-01-09.
//  MAL-45: Kanata Sequences (defseq) UI Support
//

import Foundation
import KeyPathCore

/// Configuration for key sequences (defseq)
public struct SequencesConfig: Codable, Equatable, Sendable {
    public static let minimumPauseLimitMs = 300
    public static let maximumPauseLimitMs = 2000
    public static let defaultPauseLimitMs = 500
    public static let pauseLimitStepMs = 50

    public var sequences: [SequenceDefinition]
    public var activeSequenceID: UUID?

    /// Maximum pause in milliseconds after the most recent sequence key.
    /// The persisted name is retained for configuration compatibility.
    public var globalTimeout: Int

    public init(
        sequences: [SequenceDefinition] = [],
        activeSequenceID: UUID? = nil,
        globalTimeout: Int = Self.defaultPauseLimitMs
    ) {
        self.sequences = sequences
        self.activeSequenceID = activeSequenceID
        self.globalTimeout = globalTimeout
    }

    // MARK: - Validation

    /// Validates whether the sequence pause limit is within the supported range.
    public var isValidTimeout: Bool {
        globalTimeout >= Self.minimumPauseLimitMs
            && globalTimeout <= Self.maximumPauseLimitMs
    }

    /// Safe value for runtime generation when persisted or imported data predates validation.
    public var clampedPauseLimitMs: Int {
        min(max(globalTimeout, Self.minimumPauseLimitMs), Self.maximumPauseLimitMs)
    }

    // MARK: - Preset Factory

    /// Default preset sequences (Window Management, App Launcher, Navigation)
    public static var defaultPresets: SequencesConfig {
        SequencesConfig(
            sequences: [
                .windowManagementPreset,
                .appLauncherPreset,
                .navigationPreset
            ],
            globalTimeout: defaultPauseLimitMs
        )
    }

    // MARK: - Conflict Detection

    /// Detect conflicts between sequences
    public func detectConflicts() -> [SequenceConflict] {
        var conflicts: [SequenceConflict] = []

        for i in 0 ..< sequences.count {
            for j in (i + 1) ..< sequences.count {
                let seq1 = sequences[i]
                let seq2 = sequences[j]

                // Same keys → conflict
                if seq1.keys == seq2.keys {
                    conflicts.append(SequenceConflict(
                        sequence1: seq1,
                        sequence2: seq2,
                        type: .sameKeys
                    ))
                } else if seq1.keys.starts(with: seq2.keys) || seq2.keys.starts(with: seq1.keys) {
                    // Prefix overlap (one is prefix of another) - only check if not identical
                    conflicts.append(SequenceConflict(
                        sequence1: seq1,
                        sequence2: seq2,
                        type: .prefixOverlap
                    ))
                }
            }
        }

        return conflicts
    }

    /// Whether there are any conflicts between sequences
    public var hasConflicts: Bool {
        !detectConflicts().isEmpty
    }
}

// MARK: - SequenceDefinition

/// Single sequence definition
public struct SequenceDefinition: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var keys: [String] // e.g., ["space", "w"]
    public var action: SequenceAction
    public var description: String?

    public init(
        id: UUID = UUID(),
        name: String,
        keys: [String],
        action: SequenceAction,
        description: String? = nil
    ) {
        self.id = id
        self.name = name
        self.keys = keys
        self.action = action
        self.description = description
    }

    // MARK: - Validation

    /// Whether the sequence is valid (non-empty name, 1-5 keys)
    public var isValid: Bool {
        !keys.isEmpty && keys.count <= 5 && !name.isEmpty
    }

    /// Human-readable key sequence (e.g., "Space → W")
    public var prettyKeys: String {
        keys.map(\.capitalized).joined(separator: " → ")
    }

    // MARK: - Presets

    /// Preset: Window Management (Space → W)
    public static var windowManagementPreset: SequenceDefinition {
        SequenceDefinition(
            id: UUID(uuidString: "5EEE0000-0000-0000-0000-000000000001")!,
            name: "Window Management",
            keys: ["space", "w"],
            action: .activateLayer(.custom("window")),
            description: "Activate window snapping layer"
        )
    }

    /// Preset: Navigation (Space → N)
    public static var navigationPreset: SequenceDefinition {
        SequenceDefinition(
            id: UUID(uuidString: "5EEE0000-0000-0000-0000-000000000003")!,
            name: "Navigation",
            keys: ["space", "n"],
            action: .activateLayer(.navigation),
            description: "Activate Vim navigation layer"
        )
    }

    /// Preset: App Launcher (Space → A)
    public static var appLauncherPreset: SequenceDefinition {
        SequenceDefinition(
            id: UUID(uuidString: "5EEE0000-0000-0000-0000-000000000002")!,
            name: "App Launcher",
            keys: ["space", "a"],
            action: .activateLayer(.custom("launcher")),
            description: "Activate app launcher layer"
        )
    }
}

// MARK: - SequenceAction

/// Action triggered by sequence completion
public enum SequenceAction: Codable, Equatable, Sendable {
    case activateLayer(RuleCollectionLayer)
    // Future: case actionURI(String), case macro([String])

    /// Human-readable action description
    public var displayName: String {
        switch self {
        case let .activateLayer(layer):
            "Activate \(layer.displayName)"
        }
    }
}

// MARK: - SequenceConflict

/// Conflict between two sequences
public struct SequenceConflict: Identifiable {
    public let id = UUID()
    public let sequence1: SequenceDefinition
    public let sequence2: SequenceDefinition
    public let type: ConflictType

    public enum ConflictType {
        case sameKeys // Exact same key sequence
        case prefixOverlap // One is prefix of another (timing conflict)
    }

    /// Human-readable conflict description
    public var description: String {
        switch type {
        case .sameKeys:
            "'\(sequence1.name)' and '\(sequence2.name)' use the same keys: \(sequence1.prettyKeys)"
        case .prefixOverlap:
            "'\(sequence1.name)' overlaps with '\(sequence2.name)' - may cause timing issues"
        }
    }
}
