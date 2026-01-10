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
    public var sequences: [SequenceDefinition]
    public var activeSequenceID: UUID?
    public var globalTimeout: Int  // Milliseconds

    public init(
        sequences: [SequenceDefinition] = [],
        activeSequenceID: UUID? = nil,
        globalTimeout: Int = 500
    ) {
        self.sequences = sequences
        self.activeSequenceID = activeSequenceID
        self.globalTimeout = globalTimeout
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
            globalTimeout: 500
        )
    }

    // MARK: - Conflict Detection

    /// Detect conflicts between sequences
    public func detectConflicts() -> [SequenceConflict] {
        var conflicts: [SequenceConflict] = []

        for i in 0..<sequences.count {
            for j in (i+1)..<sequences.count {
                let seq1 = sequences[i]
                let seq2 = sequences[j]

                // Same keys → conflict
                if seq1.keys == seq2.keys {
                    conflicts.append(SequenceConflict(
                        sequence1: seq1,
                        sequence2: seq2,
                        type: .sameKeys
                    ))
                }

                // Prefix overlap (one is prefix of another)
                if seq1.keys.starts(with: seq2.keys) || seq2.keys.starts(with: seq1.keys) {
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
    public var keys: [String]  // e.g., ["space", "w"]
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
        keys.map { $0.capitalized }.joined(separator: " → ")
    }

    // MARK: - Presets

    /// Preset: Window Management (Space → W)
    public static var windowManagementPreset: SequenceDefinition {
        SequenceDefinition(
            id: UUID(uuidString: "SEQ00000-0000-0000-0000-000000000001")!,
            name: "Window Management",
            keys: ["space", "w"],
            action: .activateLayer(.custom("window")),
            description: "Activate window snapping layer"
        )
    }

    /// Preset: App Launcher (Space → A)
    public static var appLauncherPreset: SequenceDefinition {
        SequenceDefinition(
            id: UUID(uuidString: "SEQ00000-0000-0000-0000-000000000002")!,
            name: "App Launcher",
            keys: ["space", "a"],
            action: .activateLayer(.custom("launcher")),
            description: "Activate app quick launch layer"
        )
    }

    /// Preset: Navigation (Space → N)
    public static var navigationPreset: SequenceDefinition {
        SequenceDefinition(
            id: UUID(uuidString: "SEQ00000-0000-0000-0000-000000000003")!,
            name: "Navigation",
            keys: ["space", "n"],
            action: .activateLayer(.navigation),
            description: "Activate Vim navigation layer"
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
        case .activateLayer(let layer):
            return "Activate \(layer.displayName)"
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
        case sameKeys      // Exact same key sequence
        case prefixOverlap // One is prefix of another (timing conflict)
    }

    /// Human-readable conflict description
    public var description: String {
        switch type {
        case .sameKeys:
            return "'\(sequence1.name)' and '\(sequence2.name)' use the same keys: \(sequence1.prettyKeys)"
        case .prefixOverlap:
            return "'\(sequence1.name)' overlaps with '\(sequence2.name)' - may cause timing issues"
        }
    }
}

// MARK: - SequenceTimeout

/// Timeout presets for sequence completion
public enum SequenceTimeout: Int, CaseIterable, Codable, Sendable {
    case fast = 300        // Experienced users
    case moderate = 500    // Default
    case relaxed = 1000    // Learning mode

    /// Display name (e.g., "Fast (300ms)")
    public var displayName: String {
        switch self {
        case .fast: return "Fast (300ms)"
        case .moderate: return "Moderate (500ms)"
        case .relaxed: return "Relaxed (1000ms)"
        }
    }

    /// Description of timeout behavior
    public var description: String {
        switch self {
        case .fast: return "For experienced users - requires quick key presses"
        case .moderate: return "Balanced timeout - works for most users"
        case .relaxed: return "Longer timeout - ideal for learning sequences"
        }
    }
}
