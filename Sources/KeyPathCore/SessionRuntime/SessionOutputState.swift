import Foundation

public struct SessionKeyOutput: Equatable, Sendable {
    public let keyCode: UInt16
    public let isDown: Bool
    public let isRepeat: Bool
    public let flags: UInt64
}

/// Tracks only keys actually emitted by this runtime. Failure cleanup releases
/// that set, never a guessed list of every key on the user's keyboard.
public struct SessionOutputState: Sendable {
    public enum Failure: Error, Equatable {
        case unsupportedEvent(page: UInt32, usage: UInt32, value: UInt64)
        case repeatWithoutPress(usage: UInt32)
    }

    public private(set) var heldUsages: Set<UInt32> = []

    public init() {}

    public var modifierFlags: UInt64 {
        heldUsages.reduce(0) { $0 | SessionKeyMap.modifierFlags(for: $1) }
    }

    public mutating func translate(
        _ event: KanataHostBridgePassthruOutputEvent
    ) throws -> SessionKeyOutput {
        guard event.usagePage == SessionKeyMap.keyboardPage,
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
