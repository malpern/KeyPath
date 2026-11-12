import Foundation
import KeyPathCore
import SwiftUI

// MARK: - InstallerServices

/// What `InstallerEngine` needs from the app: the system validator it inspects
/// with, the runtime it starts, and the uninstaller. The app and the CLI each set
/// `current` once at launch (`configureInstallerServices`); tests pass their own
/// to `InstallerEngine(services:)`. Wizard views get the rest from `WizardHost`.
@MainActor
public struct InstallerServices {
    public var systemValidator: (any WizardSystemValidating)?
    public var runtime: (any RuntimeCoordinating)?
    /// Makes a new uninstaller per uninstall. Nil where uninstall is not offered (the CLI).
    public var makeUninstaller: (() -> any WizardUninstalling)?

    public init(
        systemValidator: (any WizardSystemValidating)? = nil,
        runtime: (any RuntimeCoordinating)? = nil,
        makeUninstaller: (() -> any WizardUninstalling)? = nil
    ) {
        self.systemValidator = systemValidator
        self.runtime = runtime
        self.makeUninstaller = makeUninstaller
    }

    /// The services set at launch. `InstallerEngine()` reads it at call time, so an
    /// engine made before launch finishes still sees the configured services.
    public static var current = InstallerServices()
}

// MARK: - Environment Keys

/// Environment key for RuntimeCoordinating, replacing @Environment(KanataViewModel.self)
private struct RuntimeCoordinatingKey: EnvironmentKey {
    static let defaultValue: (any RuntimeCoordinating)? = nil
}

public extension EnvironmentValues {
    var runtimeCoordinator: (any RuntimeCoordinating)? {
        get { self[RuntimeCoordinatingKey.self] }
        set { self[RuntimeCoordinatingKey.self] = newValue }
    }
}
