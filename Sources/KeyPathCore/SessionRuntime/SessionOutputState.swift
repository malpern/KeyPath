import Foundation

/// Function-key events carry the Function flag even when physical Fn is not
/// held. Only Fn's own flagsChanged event establishes passthrough Fn state.
public struct SessionPhysicalModifierState: Sendable {
    private var fnHeld = false

    public init() {}

    public mutating func passthroughFlags(keyCode: UInt16, isFlagsChanged: Bool, flags: UInt64) -> UInt64 {
        if keyCode == 63, isFlagsChanged { fnHeld = flags & (1 << 23) != 0 }
        return (flags & (1 << 16)) | (fnHeld ? (1 << 23) : 0)
    }
}

public struct SessionKeyOutput: Equatable, Sendable {
    public let keyCode: UInt16
    public let isDown: Bool
    public let isRepeat: Bool
    public let flags: UInt64
}

/// A media key the worker posts as a system-defined event. No repeat: macOS
/// repeats a held media key itself (driverless-media-keys.md §2c).
public struct SessionMediaOutput: Equatable, Sendable {
    public let usage: UInt32
    /// `NX_KEYTYPE_*`, from `SessionKeyMap.mediaKeyType(forUsage:)`.
    public let keyType: Int
    public let isDown: Bool

    public init(usage: UInt32, keyType: Int, isDown: Bool) {
        self.usage = usage
        self.keyType = keyType
        self.isDown = isDown
    }
}

/// Tracks only keys actually emitted by this runtime. Failure cleanup releases
/// that set, never a guessed list of every key on the user's keyboard.
public struct SessionOutputState: Sendable {
    public enum Failure: Error, Equatable {
        case unsupportedEvent(page: UInt32, usage: UInt32, value: UInt64)
        case repeatWithoutPress(usage: UInt32)
    }

    public private(set) var heldUsages: Set<UInt32> = []
    /// Consumer-page media keys currently down, released like keys on cleanup.
    public private(set) var heldMediaUsages: Set<UInt32> = []

    public init() {}

    /// A consumer-page event as the media output to post, or nil for a repeat
    /// (dropped: the system repeats a held media key on its own).
    public mutating func translateMedia(_ event: KanataHostBridgePassthruOutputEvent) throws -> SessionMediaOutput? {
        guard event.usagePage == SessionKeyMap.consumerPage,
              let keyType = SessionKeyMap.mediaKeyType(forUsage: event.usage), event.value <= 2
        else {
            throw Failure.unsupportedEvent(page: event.usagePage, usage: event.usage, value: event.value)
        }
        if event.value == 2 {
            guard heldMediaUsages.contains(event.usage) else { throw Failure.repeatWithoutPress(usage: event.usage) }
            return nil
        }
        if event.value == 0 {
            heldMediaUsages.remove(event.usage)
        } else {
            heldMediaUsages.insert(event.usage)
        }
        return SessionMediaOutput(usage: event.usage, keyType: keyType, isDown: event.value != 0)
    }

    public mutating func releaseAllMedia() -> [SessionMediaOutput] {
        heldMediaUsages.sorted().compactMap { usage in
            try? translateMedia(.init(value: 0, usagePage: SessionKeyMap.consumerPage, usage: usage)) ?? nil
        }
    }

    public var modifierFlags: UInt64 {
        heldUsages.reduce(0) { $0 | SessionKeyMap.modifierFlags(for: $1) }
    }

    public mutating func translate(
        _ event: KanataHostBridgePassthruOutputEvent
    ) throws -> SessionKeyOutput {
        guard event.usagePage == SessionKeyMap.keyboardPage,
              // Caps changes WindowServer's latch upstream of this tap. Even
              // a managed Caps input must never synthesize a Caps output.
              event.usage != 57,
              let code = SessionKeyMap.keyCode(forUsage: event.usage), event.value <= 2
        else {
            throw Failure.unsupportedEvent(page: event.usagePage, usage: event.usage, value: event.value)
        }
        if event.value == 2, !heldUsages.contains(event.usage) {
            throw Failure.repeatWithoutPress(usage: event.usage)
        }
        if event.value == 0 {
            heldUsages.remove(event.usage)
        } else {
            heldUsages.insert(event.usage)
        }
        return SessionKeyOutput(
            keyCode: code, isDown: event.value != 0,
            isRepeat: event.value == 2, flags: modifierFlags
        )
    }

    public mutating func releaseAll() -> [SessionKeyOutput] {
        // Release ordinary keys first while their output modifiers still apply.
        let usages = heldUsages.sorted {
            let lhs = SessionKeyMap.isModifier($0)
            let rhs = SessionKeyMap.isModifier($1)
            return lhs == rhs ? $0 < $1 : !lhs
        }
        return usages.compactMap { usage in
            try? translate(.init(value: 0, usagePage: SessionKeyMap.keyboardPage, usage: usage))
        }
    }
}
