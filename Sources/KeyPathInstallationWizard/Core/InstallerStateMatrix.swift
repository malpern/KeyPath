import Foundation
import KeyPathCore
import KeyPathWizardCore

/// Rows from `docs/process/installer-repair-state-matrix.md`.
public enum InstallerStateMatrixRow: String, CaseIterable, Sendable, Equatable {
    case sessionRuntimeStopped = "Session runtime stopped or not ready"
    case sessionRuntimeReady = "Session tap active and TCP responding"
}

/// A value captured from system evidence, preserving the difference between
/// "known false" and "not captured".
public enum Evidence<Value: Sendable & Equatable>: Sendable, Equatable {
    case known(Value)
    case unknown
}

public extension Evidence {
    var value: Value? {
        guard case let .known(value) = self else { return nil }
        return value
    }
}

public extension Evidence where Value == Bool {
    static var present: Evidence<Bool> {
        .known(true)
    }

    static var absent: Evidence<Bool> {
        .known(false)
    }

    var isKnownTrue: Bool {
        value == true
    }

    var isKnownFalse: Bool {
        value == false
    }
}

extension Evidence: ExpressibleByBooleanLiteral where Value == Bool {
    public init(booleanLiteral value: Bool) {
        self = .known(value)
    }
}

/// Minimal immutable evidence used by the state-matrix classifier.
///
/// This is intentionally pure and OS-free. Production construction spells out
/// every field so omitted evidence can never default to healthy.
public struct InstallerStateMatrixSnapshot: Sendable, Equatable {
    /// Whether the canonical capture finished; an incomplete capture is never ready.
    public var captureComplete: Evidence<Bool>
    public var sessionInputCaptureReady: Evidence<Bool>
    public var kanataBinaryPresent: Evidence<Bool>
    public var requiredRuntimePayloadPresent: Evidence<Bool>
    public var kanataProcessRunning: Evidence<Bool>
    public var kanataTCPResponding: Evidence<Bool>

    public init(
        captureComplete: Evidence<Bool>,
        sessionInputCaptureReady: Evidence<Bool>,
        kanataBinaryPresent: Evidence<Bool>,
        requiredRuntimePayloadPresent: Evidence<Bool>,
        kanataProcessRunning: Evidence<Bool>,
        kanataTCPResponding: Evidence<Bool>
    ) {
        self.captureComplete = captureComplete
        self.sessionInputCaptureReady = sessionInputCaptureReady
        self.kanataBinaryPresent = kanataBinaryPresent
        self.requiredRuntimePayloadPresent = requiredRuntimePayloadPresent
        self.kanataProcessRunning = kanataProcessRunning
        self.kanataTCPResponding = kanataTCPResponding
    }

    public var runtimeReady: Bool {
        kanataProcessRunning.isKnownTrue && kanataTCPResponding.isKnownTrue
    }
}

public enum InstallerStateMatrixAction: String, Sendable, Equatable {
    case restartOrRecoverKanataRuntime = "restart-or-recover-kanata-runtime"
}

public enum InstallerStateMatrixPlanner {
    public static func classify(_ snapshot: InstallerStateMatrixSnapshot) -> InstallerStateMatrixRow {
        snapshot.captureComplete.isKnownTrue
            && snapshot.kanataBinaryPresent.isKnownTrue
            && snapshot.requiredRuntimePayloadPresent.isKnownTrue
            && snapshot.runtimeReady && snapshot.sessionInputCaptureReady.isKnownTrue
            ? .sessionRuntimeReady : .sessionRuntimeStopped
    }

    public static func plan(for row: InstallerStateMatrixRow) -> [InstallerStateMatrixAction] {
        switch row {
        case .sessionRuntimeStopped: [.restartOrRecoverKanataRuntime]
        case .sessionRuntimeReady: []
        }
    }

    public static func plan(for snapshot: InstallerStateMatrixSnapshot) -> [InstallerStateMatrixAction] {
        plan(for: classify(snapshot))
    }
}

public extension SystemContext {
    var installerStateMatrixSnapshot: InstallerStateMatrixSnapshot {
        InstallerStateMatrixSnapshot(
            captureComplete: .known(captureStatus.isComplete),
            sessionInputCaptureReady: .known(services.kanataRuntimeReadiness.inputCaptureReady),
            kanataBinaryPresent: .known(components.kanataBinaryInstalled),
            requiredRuntimePayloadPresent: .known(components.requiredRuntimePayloadPresent),
            kanataProcessRunning: services.kanataProcessRunning.map(Evidence<Bool>.known) ?? .unknown,
            kanataTCPResponding: services.kanataTCPResponding.map(Evidence<Bool>.known) ?? .unknown
        )
    }

    var installerStateMatrixRow: InstallerStateMatrixRow {
        InstallerStateMatrixPlanner.classify(installerStateMatrixSnapshot)
    }

    var installerStateMatrixPlan: [InstallerStateMatrixAction] {
        InstallerStateMatrixPlanner.plan(for: installerStateMatrixRow)
    }
}
