import Foundation
import KeyPathCore

/// Installs `keypath-cli` as a link in `~/.local/bin`, pointing at the signed CLI
/// inside KeyPath.app. It is the user's own folder, so installing needs no
/// administrator password and uninstalling can remove the link.
enum CommandLineToolInstaller {
    enum InstallError: LocalizedError {
        case bundledToolMissing(String)
        case destinationConflict(String)

        var errorDescription: String? {
            switch self {
            case let .bundledToolMissing(path):
                "The bundled command-line tool was not found at \(path)."
            case let .destinationConflict(path):
                "\(path) already exists and is not a KeyPath command-line tool link."
            }
        }
    }

    static func linkPath(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        home.appendingPathComponent(".local/bin/keypath-cli").path
    }

    /// Where versions before 2026-11 installed the link. It is root-owned, so
    /// KeyPath leaves it alone; the docs say how to remove it.
    static let legacyLinkPath = "/usr/local/bin/keypath-cli"

    /// The line that puts the link's folder on a zsh or bash PATH.
    static let pathExportLine = #"export PATH="$HOME/.local/bin:$PATH""#

    static var bundledToolPath: String {
        "\(Bundle.main.bundlePath)/Contents/MacOS/keypath-cli"
    }

    static func canReplaceExistingDestination(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let path = linkPath(home: home)
        var info = stat()
        guard lstat(path, &info) == 0 else { return true }
        return pointsIntoKeyPathApp(destination(ofLinkAt: path))
    }

    static func install(
        toolPath: String = bundledToolPath,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws {
        let files = FileManager.default
        guard files.isExecutableFile(atPath: toolPath) else {
            throw InstallError.bundledToolMissing(toolPath)
        }
        let path = linkPath(home: home)
        guard canReplaceExistingDestination(home: home) else {
            throw InstallError.destinationConflict(path)
        }
        try files.createDirectory(
            at: URL(fileURLWithPath: path).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Make the new link beside the old one, then rename it into place, so a
        // failure never leaves the user without a working link.
        let staged = path + ".keypath-\(UUID().uuidString)"
        try files.createSymbolicLink(atPath: staged, withDestinationPath: toolPath)
        guard rename(staged, path) == 0 else {
            let reason = String(cString: strerror(errno))
            try? files.removeItem(atPath: staged)
            throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: "Could not install \(path): \(reason)"])
        }
    }

    /// Removes the link when it points at `toolPath` (the copy being uninstalled)
    /// or at a KeyPath that no longer exists. A link to another installed copy,
    /// and anything that is not KeyPath's link, is left alone.
    @discardableResult
    static func uninstall(
        toolPath: String = bundledToolPath,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> Bool {
        let path = linkPath(home: home)
        guard let target = destination(ofLinkAt: path), pointsIntoKeyPathApp(target) else { return false }
        guard target == toolPath || !FileManager.default.fileExists(atPath: target) else { return false }
        try FileManager.default.removeItem(atPath: path)
        return true
    }

    private static func destination(ofLinkAt path: String) -> String? {
        try? FileManager.default.destinationOfSymbolicLink(atPath: path)
    }

    private static func pointsIntoKeyPathApp(_ destination: String?) -> Bool {
        destination?.hasSuffix("/KeyPath.app/Contents/MacOS/keypath-cli") ?? false
    }
}
