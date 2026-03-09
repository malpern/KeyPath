import Foundation

/// Describes a prepared privileged output-bridge session for a future split runtime.
///
/// The bundled user-session host will eventually connect to `socketPath` to hand
/// remapped output to a privileged companion that can reach pqrs VirtualHID.
public struct KanataOutputBridgeSession: Equatable, Sendable, Codable {
    public let sessionID: String
    public let socketPath: String
    public let socketDirectory: String
    public let hostPID: Int32
    public let hostUID: UInt32
    public let hostGID: UInt32
    public let detail: String?

    public init(
        sessionID: String,
        socketPath: String,
        socketDirectory: String,
        hostPID: Int32,
        hostUID: UInt32,
        hostGID: UInt32,
        detail: String? = nil
    ) {
        self.sessionID = sessionID
        self.socketPath = socketPath
        self.socketDirectory = socketDirectory
        self.hostPID = hostPID
        self.hostUID = hostUID
        self.hostGID = hostGID
        self.detail = detail
    }
}
