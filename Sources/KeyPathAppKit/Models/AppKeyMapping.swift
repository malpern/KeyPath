import CryptoKit
import Foundation

/// Represents a mapping from an application to its virtual key for app-specific keymaps.
///
/// See ADR-027 for the full architecture.
public struct AppKeyMapping: Codable, Identifiable, Sendable, Equatable {
    /// Unique identifier for this mapping
    public let id: UUID

    /// The application's bundle identifier (e.g., "com.apple.Safari")
    public let bundleIdentifier: String

    /// The display name of the application (e.g., "Safari")
    public let displayName: String

    /// The virtual key name used in Kanata config (e.g., "vk_safari")
    public let virtualKeyName: String

    /// When this mapping was created
    public let createdAt: Date

    /// When this mapping was last modified
    public var modifiedAt: Date

    /// Whether this mapping is currently enabled
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        bundleIdentifier: String,
        displayName: String,
        virtualKeyName: String? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        isEnabled: Bool = true
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.virtualKeyName = virtualKeyName ?? Self.generateVirtualKeyName(
            displayName: displayName,
            bundleIdentifier: bundleIdentifier
        )
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.isEnabled = isEnabled
    }

    /// Generate a virtual key name from the app's display name.
    /// Slugifies the name (lowercase, underscores for spaces/special chars).
    /// Appends bundle ID hash on collision (handled externally).
    ///
    /// - Parameters:
    ///   - displayName: The app's display name (e.g., "Safari")
    ///   - bundleIdentifier: The app's bundle ID (used for fallback if name is empty)
    /// - Returns: A valid Kanata virtual key name (e.g., "vk_safari")
    public static func generateVirtualKeyName(displayName: String, bundleIdentifier: String) -> String {
        // Use display name, or fall back to last component of bundle ID
        let nameSource = displayName.isEmpty
            ? bundleIdentifier.split(separator: ".").last.map(String.init) ?? "unknown"
            : displayName

        let slugified = nameSource
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
            .filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }

        // Handle empty result after filtering
        guard !slugified.isEmpty else {
            // Use deterministic hash of bundle ID as fallback
            let hash = stableHash(bundleIdentifier).prefix(8)
            return "vk_app_\(hash)"
        }

        // Ensure it starts with a letter (Kanata requirement)
        let safeName = slugified.first?.isLetter == true ? slugified : "app_\(slugified)"

        return "vk_\(safeName)"
    }

    /// Generate a unique virtual key name by appending a deterministic hash of the bundle ID.
    /// Used when there's a collision with another app's virtual key name.
    ///
    /// Uses SHA256 for stable, deterministic hashing across process restarts.
    public static func generateUniqueVirtualKeyName(displayName: String, bundleIdentifier: String) -> String {
        let baseName = generateVirtualKeyName(displayName: displayName, bundleIdentifier: bundleIdentifier)
        let hash = stableHash(bundleIdentifier).prefix(6)
        return "\(baseName)_\(hash)"
    }

    /// Generate a stable, deterministic hash from a string.
    /// Uses SHA256 truncated to hex string - stable across process restarts.
    private static func stableHash(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        // Take first 8 bytes and convert to hex
        return hash.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Key Overrides

/// A single key override for an app-specific keymap.
/// Maps an input key to an output action when the app is active.
public struct AppKeyOverride: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID

    /// The input key (e.g., "j", "k", "semicolon")
    public let inputKey: String

    /// The output action - any valid Kanata action (e.g., "down", "(macro h e l l o)")
    public let outputAction: String

    /// Optional description for this override
    public var description: String?

    public init(
        id: UUID = UUID(),
        inputKey: String,
        outputAction: String,
        description: String? = nil
    ) {
        self.id = id
        self.inputKey = inputKey
        self.outputAction = outputAction
        self.description = description
    }
}

// MARK: - App Keymap

/// A complete app-specific keymap containing the app mapping and its key overrides.
public struct AppKeymap: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID

    /// The app this keymap applies to
    public var mapping: AppKeyMapping

    /// The key overrides for this app
    public var overrides: [AppKeyOverride]

    public init(
        id: UUID = UUID(),
        mapping: AppKeyMapping,
        overrides: [AppKeyOverride] = []
    ) {
        self.id = id
        self.mapping = mapping
        self.overrides = overrides
    }

    /// Convenience initializer from bundle ID and display name
    public init(
        bundleIdentifier: String,
        displayName: String,
        overrides: [AppKeyOverride] = []
    ) {
        self.id = UUID()
        self.mapping = AppKeyMapping(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName
        )
        self.overrides = overrides
    }
}
