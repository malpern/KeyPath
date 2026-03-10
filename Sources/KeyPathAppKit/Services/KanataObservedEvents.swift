import Foundation

struct KanataObservedKeyInput: Sendable, Equatable {
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

    static func from(userInfo: [AnyHashable: Any]?) -> KeypressObservationMetadata {
        KeypressObservationMetadata(
            listenerSessionID: userInfo?["listenerSessionID"] as? Int,
            kanataTimestamp: userInfo?["kanataTimestamp"] as? UInt64,
            observedAt: userInfo?["observedAt"] as? Date
        )
    }
}
