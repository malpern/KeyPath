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

struct KanataLayerChange: NotificationCenter.MainActorMessage {
    typealias Subject = NSObject

    enum Source: String {
        case kanata
        case push
    }

    let layerName: String
    let source: Source
}

/// A layer observation from the engine, even when the layer has not changed.
struct KanataHeartbeat: NotificationCenter.MainActorMessage {
    typealias Subject = NSObject
}

struct KanataMessagePush: NotificationCenter.MainActorMessage {
    typealias Subject = NSObject

    let message: String
}

struct KanataCapabilitiesUpdate: NotificationCenter.MainActorMessage {
    typealias Subject = NSObject

    let capabilities: [String]
}

struct KanataGrabStatus: NotificationCenter.MainActorMessage {
    typealias Subject = NSObject

    let active: Bool
    let reason: String?
}

struct KanataActionDispatched: NotificationCenter.MainActorMessage {
    typealias Subject = NSObject

    let uri: KeyPathActionURI
}

extension KanataHrmTraceEvent: NotificationCenter.MainActorMessage {
    public typealias Subject = NSObject
}
