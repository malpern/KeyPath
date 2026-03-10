import Foundation

/// Versioned wire contract for the future privileged Kanata output bridge.
///
/// These types are transport-agnostic. They can be serialized over a UNIX socket,
/// XPC stream, or another framed IPC transport without changing the higher-level
/// split-runtime contract.
public enum KanataOutputBridgeProtocol {
    public static let version = 1
}

public struct KanataOutputBridgeHandshake: Codable, Equatable, Sendable {
    public let version: Int
    public let sessionID: String
    public let hostPID: Int32

    public init(
        version: Int = KanataOutputBridgeProtocol.version,
        sessionID: String,
        hostPID: Int32
    ) {
        self.version = version
        self.sessionID = sessionID
        self.hostPID = hostPID
    }
}

public enum KanataOutputBridgeRequest: Codable, Equatable, Sendable {
    case handshake(KanataOutputBridgeHandshake)
    case emitKey(KanataOutputBridgeKeyEvent)
    case syncModifiers(KanataOutputBridgeModifierState)
    case reset
    case ping
}

public enum KanataOutputBridgeResponse: Codable, Equatable, Sendable {
    case ready(version: Int)
    case acknowledged(sequence: UInt64?)
    case error(KanataOutputBridgeError)
    case pong
}

public struct KanataOutputBridgeKeyEvent: Codable, Equatable, Sendable {
    public enum Action: String, Codable, Sendable {
        case keyDown
        case keyUp
    }

    public let usagePage: UInt32
    public let usage: UInt32
    public let action: Action
    public let sequence: UInt64

    public init(
        usagePage: UInt32,
        usage: UInt32,
        action: Action,
        sequence: UInt64
    ) {
        self.usagePage = usagePage
        self.usage = usage
        self.action = action
        self.sequence = sequence
    }
}

public struct KanataOutputBridgeModifierState: Codable, Equatable, Sendable {
    public let leftControl: Bool
    public let leftShift: Bool
    public let leftAlt: Bool
    public let leftCommand: Bool
    public let rightControl: Bool
    public let rightShift: Bool
    public let rightAlt: Bool
    public let rightCommand: Bool

    public init(
        leftControl: Bool = false,
        leftShift: Bool = false,
        leftAlt: Bool = false,
        leftCommand: Bool = false,
        rightControl: Bool = false,
        rightShift: Bool = false,
        rightAlt: Bool = false,
        rightCommand: Bool = false
    ) {
        self.leftControl = leftControl
        self.leftShift = leftShift
        self.leftAlt = leftAlt
        self.leftCommand = leftCommand
        self.rightControl = rightControl
        self.rightShift = rightShift
        self.rightAlt = rightAlt
        self.rightCommand = rightCommand
    }
}

public struct KanataOutputBridgeError: Codable, Equatable, Sendable {
    public let code: String
    public let message: String
    public let detail: String?

    public init(code: String, message: String, detail: String? = nil) {
        self.code = code
        self.message = message
        self.detail = detail
    }
}
