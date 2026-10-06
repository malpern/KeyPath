import AppKit
import KeyPathWizardCore

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
    private let files = FileManager.default

    init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        app: URL = Bundle.main.bundleURL,
        defaults: UserDefaults = .standard,
        domain: String = "com.keypath.KeyPath",
        prepare: @escaping () async -> Bool,
        resume: @escaping () async -> Void,
        trash: @escaping (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) {
        self.home = home
        self.app = app
        self.defaults = defaults
        self.domain = domain
        self.prepare = prepare
        self.resume = resume
        self.trash = trash
    }

    func performUninstall(deleteConfig: Bool, removeVirtualHID: Bool, allowAdminFallback: Bool) async -> WizardUninstallResult {
        guard deleteConfig, !removeVirtualHID, !allowAdminFallback else {
            return WizardUninstallResult(success: false, failureReason: "Driverless uninstall requires a settings backup and does not remove shared system components.")
        }
        guard app.pathExtension == "app", Bundle(url: app)?.bundleIdentifier == "com.keypath.KeyPath" else {
            return WizardUninstallResult(success: false, failureReason: "Run Uninstall from the installed KeyPath app.")
        }
        let paths = [".config/keypath", "Library/Application Support/KeyPath", "Library/Caches/com.keypath.KeyPath"]
        // Removing a child of a linked parent would remove external data, not
        // the link. Refuse that layout; a linked leaf itself is safe to detach.
        for path in paths {
            var parent = home.appendingPathComponent(path).deletingLastPathComponent()
            while parent.path != home.path, parent.path != "/" {
                if (try? files.attributesOfItem(atPath: parent.path)[.type]) as? FileAttributeType == .typeSymbolicLink {
                    return WizardUninstallResult(success: false, failureReason: "Settings are inside a linked folder (\(parent.path)). Nothing was removed. Move KeyPath's settings to a local folder before uninstalling.")
                }
                parent.deleteLastPathComponent()
            }
        }
        guard await prepare() else {
            await resume()
            return WizardUninstallResult(success: false, failureReason: "Keyboard cleanup could not be verified. Nothing was removed. Try again after releasing all keys.")
        }

        let backup = home.appendingPathComponent("Downloads/KeyPath-Uninstall-Backup-\(UUID().uuidString)", isDirectory: true)
        do {
            try files.createDirectory(at: backup, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            // Copy everything before deleting anything. Resolve a top-level config
            // symlink for backup, but remove only that link during cleanup.
            for (index, path) in paths.enumerated() {
                let source = home.appendingPathComponent(path)
                if files.fileExists(atPath: source.path) {
                    try files.copyItem(at: source.resolvingSymlinksInPath(), to: backup.appendingPathComponent("\(index)-\(source.lastPathComponent)"))
                }
            }
            let preferences = defaults.persistentDomain(forName: domain) ?? [:]
            let data = try PropertyListSerialization.data(fromPropertyList: preferences, format: .xml, options: 0)
            try data.write(to: backup.appendingPathComponent("preferences.plist"), options: .atomic)
            let receipt = "KeyPath uninstall backup\nPreferences domain: \(domain)\nPaths:\n\(paths.joined(separator: "\n"))\nExternal symlink targets are preserved. macOS permission grants are unchanged.\n"
            try receipt.write(to: backup.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
        } catch {
            await resume()
            return WizardUninstallResult(success: false, failureReason: "Backup failed; nothing was removed. \(error.localizedDescription)")
        }

        do {
            for path in paths {
                let source = home.appendingPathComponent(path)
                // lstat-style lookup also finds dangling symlinks.
                if (try? files.attributesOfItem(atPath: source.path)) != nil {
                    try files.removeItem(at: source)
                }
            }
            defaults.removePersistentDomain(forName: domain)
            guard defaults.synchronize() else {
                throw NSError(domain: "KeyPathUninstall", code: 1, userInfo: [NSLocalizedDescriptionKey: "Preferences could not be saved."])
            }
            try trash(app)
            guard !files.fileExists(atPath: app.path) else {
                throw CocoaError(.fileWriteUnknown)
            }
            return WizardUninstallResult(success: true, logs: ["Backup saved to \(backup.path)"])
        } catch {
            await resume()
            return WizardUninstallResult(success: false, failureReason: "Uninstall could not finish. Your backup is at \(backup.path). \(error.localizedDescription)", logs: ["Backup saved to \(backup.path)"])
        }
    }
}
