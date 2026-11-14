import Foundation
import KeyPathCore
import Security

/// Checks a session worker's launch arguments before it loads a config.
///
/// The worker is the signed KeyPath binary, so it holds the user's
/// Accessibility grant. Any process running as the user could launch it with
/// arguments of its own. The worker therefore runs only the user's canonical
/// config, and only for an owner whose running code satisfies KeyPath's own
/// designated requirement: the KeyPath app that launched it.
enum SessionWorkerLaunchCheck {
    enum Refusal: String {
        case nonCanonicalConfig = "non-canonical-config"
        case ownerNotKeyPath = "owner-not-keypath"
    }

    /// The canonical path, compared after resolving symlinks and `..`.
    static func refusal(configPath: String, canonicalConfigPath: String = KeyPathConstants.Config.mainConfigPath,
                        ownerPID: Int32,
                        ownerSatisfiesOwnRequirement: (Int32) -> Bool = ownerSatisfiesOwnRequirement) -> Refusal?
    {
        guard resolved(configPath) == resolved(canonicalConfigPath) else { return .nonCanonicalConfig }
        guard ownerPID > 0, ownerSatisfiesOwnRequirement(ownerPID) else { return .ownerNotKeyPath }
        return nil
    }

    static func resolved(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
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
