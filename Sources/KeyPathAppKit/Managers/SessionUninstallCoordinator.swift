import AppKit
import KeyPathCore
import KeyPathWizardCore

/// What a sweep of this user's KeyPath session workers proved.
enum SessionWorkerSweepResult: Equatable, Sendable {
    case noneRunning
    case stillRunning
    /// The process table could not be read, so absence is unproven.
    case unverified
}

/// Skips sockets when backing up settings. Application Support holds live
/// endpoints (the CLI's `runtime.sock`, and an engine socket a killed worker
/// left behind) that are not settings, and `FileManager` cannot copy them:
/// one socket failed the whole backup, so uninstall refused.
private final class SocketSkippingCopyDelegate: NSObject, FileManagerDelegate {
    nonisolated func fileManager(_: FileManager, shouldCopyItemAt source: URL, to _: URL) -> Bool {
        var info = stat()
        guard lstat(source.path, &info) == 0 else { return true }
        return info.st_mode & S_IFMT != S_IFSOCK
    }
}

/// Removes only the current user's driverless installation. No privileged cleanup.
@MainActor
final class SessionUninstallCoordinator: WizardUninstalling {
    private let home: URL
    private let app: URL
    private let defaults: UserDefaults
    private let domain: String
    private let prepare: () async -> Bool
    private let resume: () async -> Void
    private let trash: (URL) throws -> Void
    private let removeLoginItem: () async throws -> Void
    private let stopSessionWorkers: () async -> SessionWorkerSweepResult
    private let files = FileManager.default

    init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        app: URL = Bundle.main.bundleURL,
        defaults: UserDefaults = .standard,
        domain: String = "com.keypath.KeyPath",
        prepare: @escaping () async -> Bool,
        resume: @escaping () async -> Void,
        removeLoginItem: @escaping () async throws -> Void = {},
        stopSessionWorkers: @escaping () async -> SessionWorkerSweepResult = { .noneRunning },
        trash: @escaping (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) {
        self.home = home
        self.app = app
        self.defaults = defaults
        self.domain = domain
        self.prepare = prepare
        self.resume = resume
        self.trash = trash
        self.removeLoginItem = removeLoginItem
        self.stopSessionWorkers = stopSessionWorkers
    }

    nonisolated static func copySkippingSockets(from source: URL, to destination: URL) throws {
        let copier = FileManager()
        let delegate = SocketSkippingCopyDelegate()
        copier.delegate = delegate
        try withExtendedLifetime(delegate) { try copier.copyItem(at: source, to: destination) }
    }

    func performUninstall(deleteConfig: Bool) async -> WizardUninstallResult {
        guard deleteConfig else {
            return WizardUninstallResult(success: false, failureReason: String(localized: "Driverless uninstall requires a settings backup and does not remove shared system components."))
        }
        guard app.pathExtension == "app", Bundle(url: app)?.bundleIdentifier == "com.keypath.KeyPath" else {
            return WizardUninstallResult(success: false, failureReason: String(localized: "Run Uninstall from the installed KeyPath app."))
        }
        let paths = [".config/keypath", "Library/Application Support/KeyPath", "Library/Caches/com.keypath.KeyPath"]
        // Removing a child of a linked parent would remove external data, not
        // the link. Refuse that layout; a linked leaf itself is safe to detach.
        for path in paths {
            var parent = home.appendingPathComponent(path).deletingLastPathComponent()
            while parent.path != home.path, parent.path != "/" {
                if (try? files.attributesOfItem(atPath: parent.path)[.type]) as? FileAttributeType == .typeSymbolicLink {
                    return WizardUninstallResult(
                        success: false,
                        failureReason: String(localized: "Settings are inside a linked folder (\(parent.path)). Nothing was removed. Move KeyPath's settings to a local folder before uninstalling.")
                    )
                }
                parent.deleteLastPathComponent()
            }
        }
        guard await prepare() else {
            await resume()
            return WizardUninstallResult(success: false, failureReason: String(localized: "Keyboard cleanup could not be verified. Nothing was removed. Try again after releasing all keys."))
        }
        // prepare stops only the worker the live app tracks. Orphans of an
        // earlier app process, or probes it abandoned, would otherwise keep
        // running from the trashed bundle.
        switch await stopSessionWorkers() {
        case .noneRunning:
            break
        case .stillRunning:
            await resume()
            return WizardUninstallResult(success: false, failureReason: String(localized: "A KeyPath keyboard process did not stop. Nothing was removed. Restart your Mac, then try again."))
        case .unverified:
            await resume()
            return WizardUninstallResult(success: false, failureReason: String(localized: "KeyPath could not check which of its processes are running. Nothing was removed. Try again."))
        }

        let backup = home.appendingPathComponent("Downloads/KeyPath-Uninstall-Backup-\(UUID().uuidString)", isDirectory: true)
        do {
            try files.createDirectory(at: backup, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            // Copy everything before deleting anything. Resolve a top-level config
            // symlink for backup, but remove only that link during cleanup.
            for (index, path) in paths.enumerated() {
                let source = home.appendingPathComponent(path)
                if files.fileExists(atPath: source.path) {
                    try Self.copySkippingSockets(from: source.resolvingSymlinksInPath(),
                                                 to: backup.appendingPathComponent("\(index)-\(source.lastPathComponent)"))
                }
            }
            let preferences = defaults.persistentDomain(forName: domain) ?? [:]
            let data = try PropertyListSerialization.data(fromPropertyList: preferences, format: .xml, options: 0)
            try data.write(to: backup.appendingPathComponent("preferences.plist"), options: .atomic)
            let receipt = "KeyPath uninstall backup\nPreferences domain: \(domain)\nPaths:\n\(paths.joined(separator: "\n"))\nExternal symlink targets are preserved. macOS permission grants are unchanged.\n"
            try receipt.write(to: backup.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
        } catch {
            await resume()
            return WizardUninstallResult(success: false, failureReason: String(localized: "Backup failed; nothing was removed. \(error.localizedDescription)"))
        }

        do {
            // Leave data and the app intact if login-item removal cannot be verified.
            try await removeLoginItem()
            for path in paths {
                let source = home.appendingPathComponent(path)
                // lstat-style lookup also finds dangling symlinks.
                if (try? files.attributesOfItem(atPath: source.path)) != nil {
                    try files.removeItem(at: source)
                }
            }
            // The command-line link points into the app that is about to be
            // trashed. It is a convenience, so a failure is logged, not fatal.
            do {
                try CommandLineToolInstaller.uninstall(
                    toolPath: app.appendingPathComponent("Contents/MacOS/keypath-cli").path,
                    home: home
                )
            } catch {
                AppLogger.shared.warn("[Uninstall] Could not remove the keypath-cli link: \(error.localizedDescription)")
            }
            defaults.removePersistentDomain(forName: domain)
            guard defaults.synchronize() else {
                throw NSError(domain: "KeyPathUninstall", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Preferences could not be saved.")])
            }
            try trash(app)
            guard !files.fileExists(atPath: app.path) else {
                throw CocoaError(.fileWriteUnknown)
            }
            // Success means nothing is left running, so check again at the end.
            // No resume() here, unlike the paths above: the app and its settings
            // are gone, so there is nothing to resume watching or starting.
            let finalSweep = await stopSessionWorkers()
            guard finalSweep == .noneRunning else {
                let failureReason = finalSweep == .stillRunning
                    ? String(localized: "KeyPath was removed, but a KeyPath keyboard process is still running. Restart your Mac to stop it. Your backup is at \(backup.path).")
                    : String(localized: "KeyPath was removed, but KeyPath could not check that its processes stopped. Restart your Mac to be sure. Your backup is at \(backup.path).")
                return WizardUninstallResult(
                    success: false,
                    failureReason: failureReason,
                    logs: ["Backup saved to \(backup.path)"]
                )
            }
            return WizardUninstallResult(success: true, logs: ["Backup saved to \(backup.path)"])
        } catch {
            await resume()
            return WizardUninstallResult(
                success: false,
                failureReason: String(localized: "Uninstall could not finish. Your backup is at \(backup.path). \(error.localizedDescription)"),
                logs: ["Backup saved to \(backup.path)"]
            )
        }
    }
}
