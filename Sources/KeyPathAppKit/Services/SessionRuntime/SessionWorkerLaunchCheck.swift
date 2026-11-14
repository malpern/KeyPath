import Foundation
import KeyPathCore
import Security

/// Checks a session worker's launch arguments before it loads a config.
///
/// The worker is the signed KeyPath binary, so it holds the user's
/// Accessibility grant, and any process running as the user can launch it
/// with arguments of its own. Two checks keep such a worker harmless:
///
/// - It loads only the user's canonical config, `~/.config/keypath/keypath.kbd`,
///   compared after `realpath(3)`, with any `..` refused. So it runs the
///   user's own mappings, not mappings the launching process chose. (That file
///   is the user's, so a process running as the user can still edit it; KeyPath
///   shows the result in its UI.)
/// - Its named owner's running code must satisfy KeyPath's own designated
///   requirement. The engine socket admits only that owner (ADR-046), so the
///   launching process cannot control the worker or read its events.
///
/// The owner check does not prove that this owner launched the worker: the
/// app starts it through NSWorkspace, so its parent is launchd and no secret
/// can be passed. A worker launched against the real app's PID is a second
/// copy of the user's own runtime.
enum SessionWorkerLaunchCheck {
    enum Refusal: String {
        case nonCanonicalConfig = "non-canonical-config"
        case ownerNotKeyPath = "owner-not-keypath"
    }

    /// The account's real config, from its home directory in the user
    /// database. Not `KeyPathConstants.Config.mainConfigPath`, which test
    /// detection (environment variables such as SWIFT_TEST) redirects to a
    /// predictable sandbox a launcher could prepare.
    static var accountConfigPath: String {
        let home = getpwuid(getuid()).flatMap { $0.pointee.pw_dir.map { String(cString: $0) } } ?? NSHomeDirectory()
        return home + "/.config/keypath/" + KeyPathConstants.Config.fileName
    }

    static func refusal(configPath: String, canonicalConfigPath: String = accountConfigPath,
                        ownerPID: Int32,
                        ownerSatisfiesOwnRequirement: (Int32) -> Bool = ownerSatisfiesOwnRequirement) -> Refusal?
    {
        guard isSameFile(configPath, canonicalConfigPath) else { return .nonCanonicalConfig }
        guard ownerPID > 0, ownerSatisfiesOwnRequirement(ownerPID) else { return .ownerNotKeyPath }
        return nil
    }

    /// Paths with a `..` component are refused outright: the kernel resolves
    /// `..` after following a symlink, so a lexical comparison can name a
    /// different file. Otherwise both paths are resolved with `realpath(3)`;
    /// when a file does not exist yet, the absolute paths must match exactly.
    static func isSameFile(_ path: String, _ canonical: String) -> Bool {
        guard path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { return false }
        switch (realPath(path), realPath(canonical)) {
        case let (resolved?, resolvedCanonical?): return resolved == resolvedCanonical
        case (nil, nil): return path == canonical
        default: return false
        }
    }

    private static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// Whether the running process `pid` satisfies this process's designated requirement.
    static func ownerSatisfiesOwnRequirement(_ pid: Int32) -> Bool {
        var selfCode: SecCode?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode else { return false }
        var staticSelf: SecStaticCode?
        guard SecCodeCopyStaticCode(selfCode, [], &staticSelf) == errSecSuccess, let staticSelf else { return false }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticSelf, [], &requirement) == errSecSuccess,
              let requirement
        else { return false }

        var ownerCode: SecCode?
        let attributes = [kSecGuestAttributePid: NSNumber(value: pid)] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &ownerCode) == errSecSuccess,
              let ownerCode
        else { return false }
        return SecCodeCheckValidity(ownerCode, [], requirement) == errSecSuccess
    }
}
