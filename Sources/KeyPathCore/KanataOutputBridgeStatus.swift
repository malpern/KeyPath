import Foundation

/// Describes whether the privileged pqrs VirtualHID output boundary is available.
///
/// This is intentionally transport-agnostic so the app can keep the same contract
/// whether the information comes from `KeyPathHelper` today or a dedicated
/// privileged output companion later.
public struct KanataOutputBridgeStatus: Equatable, Sendable, Codable {
    public let available: Bool
    public let companionRunning: Bool
    public let requiresPrivilegedBridge: Bool
    public let socketDirectory: String?
    public let detail: String?

    public init(
        available: Bool,
        companionRunning: Bool,
        requiresPrivilegedBridge: Bool,
        socketDirectory: String?,
        detail: String?
    ) {
        self.available = available
        self.companionRunning = companionRunning
        self.requiresPrivilegedBridge = requiresPrivilegedBridge
        self.socketDirectory = socketDirectory
        self.detail = detail
    }

    private enum CodingKeys: String, CodingKey {
        case available
        case companionRunning
        case requiresPrivilegedBridge
        case socketDirectory
        case detail
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let available = try container.decode(Bool.self, forKey: .available)
        self.available = available
        self.companionRunning =
            try container.decodeIfPresent(Bool.self, forKey: .companionRunning) ?? available
        self.requiresPrivilegedBridge = try container.decode(Bool.self, forKey: .requiresPrivilegedBridge)
        self.socketDirectory = try container.decodeIfPresent(String.self, forKey: .socketDirectory)
        self.detail = try container.decodeIfPresent(String.self, forKey: .detail)
    }
}
