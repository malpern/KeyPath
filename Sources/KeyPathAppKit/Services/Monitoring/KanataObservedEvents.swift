import Foundation

/// Physical key events are delivered on the main actor in engine order.
struct KanataObservedKeyInput: Sendable, Equatable, NotificationCenter.MainActorMessage {
    typealias Subject = NSObject

    let key: String
    let action: KanataKeyAction
    let kanataTimestamp: UInt64?
    let sessionID: Int
    let observedAt: Date
}

struct KeypressObservationMetadata: Equatable {
    let listenerSessionID: Int?
    let kanataTimestamp: UInt64?
    let observedAt: Date?
}
