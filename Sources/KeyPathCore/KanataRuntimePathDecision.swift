import Foundation

public enum KanataRuntimePathDecision: Equatable, Sendable {
    case useSplitRuntime(reason: String)
    case useLegacySystemBinary(reason: String)
    case blocked(reason: String)

    public var reason: String {
        switch self {
        case let .useSplitRuntime(reason),
             let .useLegacySystemBinary(reason),
             let .blocked(reason):
            reason
        }
    }
}

public struct KanataRuntimePathInputs: Equatable, Sendable {
    public let hostBridgeLoaded: Bool
    public let hostConfigValid: Bool
    public let hostRuntimeConstructible: Bool
    public let helperReady: Bool
    public let outputBridgeStatus: KanataOutputBridgeStatus?
    public let legacySystemBinaryAvailable: Bool

    public init(
        hostBridgeLoaded: Bool,
        hostConfigValid: Bool,
        hostRuntimeConstructible: Bool,
        helperReady: Bool,
        outputBridgeStatus: KanataOutputBridgeStatus?,
        legacySystemBinaryAvailable: Bool
    ) {
        self.hostBridgeLoaded = hostBridgeLoaded
        self.hostConfigValid = hostConfigValid
        self.hostRuntimeConstructible = hostRuntimeConstructible
        self.helperReady = helperReady
        self.outputBridgeStatus = outputBridgeStatus
        self.legacySystemBinaryAvailable = legacySystemBinaryAvailable
    }
}

public enum KanataRuntimePathEvaluator {
    public static func decide(_ inputs: KanataRuntimePathInputs) -> KanataRuntimePathDecision {
        if inputs.hostBridgeLoaded,
           inputs.hostConfigValid,
           inputs.hostRuntimeConstructible,
           inputs.helperReady,
           let outputBridgeStatus = inputs.outputBridgeStatus,
           outputBridgeStatus.available,
           outputBridgeStatus.companionRunning,
           outputBridgeStatus.requiresPrivilegedBridge
        {
            return .useSplitRuntime(
                reason: "bundled host can own input runtime and privileged output bridge is required at \(outputBridgeStatus.socketDirectory ?? KeyPathConstants.VirtualHID.rootOnlyTmp)"
            )
        }

        if inputs.legacySystemBinaryAvailable {
            if !inputs.helperReady {
                return .useLegacySystemBinary(
                    reason: "privileged helper is not ready, so continue using the legacy system binary"
                )
            }

            if let outputBridgeStatus = inputs.outputBridgeStatus,
               outputBridgeStatus.available,
               outputBridgeStatus.requiresPrivilegedBridge
            {
                return .useLegacySystemBinary(
                    reason: outputBridgeStatus.companionRunning
                        ? "root-scoped pqrs output bridge is still required, so continue using the legacy system binary until split runtime output is implemented"
                        : "privileged output companion is installed but not healthy, so continue using the legacy system binary"
                )
            }

            if !inputs.hostBridgeLoaded || !inputs.hostConfigValid || !inputs.hostRuntimeConstructible {
                return .useLegacySystemBinary(
                    reason: "bundled host runtime is not ready yet, so continue using the legacy system binary"
                )
            }

            return .useLegacySystemBinary(
                reason: "privileged output bridge status is unavailable, so keep the legacy system binary as fallback"
            )
        }

        if !inputs.hostBridgeLoaded {
            return .blocked(reason: "bundled host bridge is unavailable and no legacy system binary exists")
        }
        if !inputs.hostConfigValid {
            return .blocked(reason: "bundled host runtime cannot validate the active config and no legacy system binary exists")
        }
        if !inputs.hostRuntimeConstructible {
            return .blocked(reason: "bundled host runtime cannot construct Kanata and no legacy system binary exists")
        }
        if !inputs.helperReady {
            return .blocked(reason: "privileged helper is unavailable and no legacy system binary exists")
        }

        return .blocked(reason: "privileged output bridge is unavailable and no legacy system binary exists")
    }
}
