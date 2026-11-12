import Foundation
import KeyPathCore
import SwiftUI

/// What the app gives the wizard's pages that the wizard module cannot build
/// itself: two pages that live in the app, the external-Kanata operations, and
/// the Accessibility request. The app's wizard hosts put one in the SwiftUI
/// environment; the default has none of them, so a page shows its fallback.
public struct WizardHost: Sendable {
    /// Signature: (onMigrationComplete(hasRunningKanata), onSkip) -> page
    public var makeKanataMigrationPage: (@MainActor @Sendable (
        @escaping (Bool) -> Void, @escaping () -> Void
    ) -> AnyView)?
    /// Signature: (onImportComplete, onSkip) -> page
    public var makeKarabinerImportPage: (@MainActor @Sendable (
        @escaping () -> Void, @escaping () -> Void
    ) -> AnyView)?
    public var externalKanata: ExternalKanataOperations?
    public var permissionRequests: (any WizardPermissionRequesting)?

    public init(
        makeKanataMigrationPage: (@MainActor @Sendable (@escaping (Bool) -> Void, @escaping () -> Void) -> AnyView)? = nil,
        makeKarabinerImportPage: (@MainActor @Sendable (@escaping () -> Void, @escaping () -> Void) -> AnyView)? = nil,
        externalKanata: ExternalKanataOperations? = nil,
        permissionRequests: (any WizardPermissionRequesting)? = nil
    ) {
        self.makeKanataMigrationPage = makeKanataMigrationPage
        self.makeKarabinerImportPage = makeKarabinerImportPage
        self.externalKanata = externalKanata
        self.permissionRequests = permissionRequests
    }
}

/// Finding and stopping a Kanata that KeyPath did not start.
public struct ExternalKanataOperations: Sendable {
    public var info: @Sendable () -> WizardSystemPaths.RunningKanataInfo?
    public var stop: @Sendable (WizardSystemPaths.RunningKanataInfo) async -> Result<Void, Error>
    public var isRunning: @Sendable () -> Bool

    public init(
        info: @escaping @Sendable () -> WizardSystemPaths.RunningKanataInfo?,
        stop: @escaping @Sendable (WizardSystemPaths.RunningKanataInfo) async -> Result<Void, Error>,
        isRunning: @escaping @Sendable () -> Bool
    ) {
        self.info = info
        self.stop = stop
        self.isRunning = isRunning
    }
}

private struct WizardHostKey: EnvironmentKey {
    static let defaultValue = WizardHost()
}

public extension EnvironmentValues {
    var wizardHost: WizardHost {
        get { self[WizardHostKey.self] }
        set { self[WizardHostKey.self] = newValue }
    }
}
