import Foundation
import Security

/// Identity of the bundled kanata binary, used to detect when a running kanata
/// daemon predates the binary KeyPath now ships (e.g. after a KeyPath upgrade or
/// redeploy) so KeyPath can restart it to adopt the new binary.
///
/// Uses the code-signing **cdhash** (`kSecCodeInfoUnique`), not a file hash or
/// mtime: a deploy re-signs the kanata binary in place, which changes the file
/// bytes/mtime even when the code is identical — a file-based signal would bounce
/// kanata on every Swift-only redeploy. The cdhash is stable across re-signs of
/// identical code and changes only when the code changes.
public enum KanataBinaryIdentity {
    /// cdhash (lowercase hex) of the signed binary at `path`, or nil if it can't
    /// be read (unsigned, missing, or query failure — caller should no-op).
    public static func codeHash(atPath path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode
        else { return nil }
        var info: CFDictionary?
        // SecCSFlags(2) == kSecCSSigningInformation, which includes the cdhash.
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: 2), &info) == errSecSuccess,
              let dict = info as? [String: Any],
              let cdhash = dict[kSecCodeInfoUnique as String] as? Data
        else { return nil }
        return cdhash.map { String(format: "%02x", $0) }.joined()
    }

    /// cdhash of the kanata binary KeyPath currently bundles, or nil if unavailable.
    public static func bundledCodeHash() -> String? {
        codeHash(atPath: WizardSystemPaths.bundledKanataPath)
    }

    /// Whether the running kanata should be restarted to adopt the bundled
    /// binary. True when the bundled identity is known and differs from what
    /// KeyPath last adopted — including the first run with no record yet, which
    /// covers a daemon that was already running an older binary. False when the
    /// bundled identity can't be determined (don't act on uncertainty).
    public static func shouldAdoptBundled(adopted: String?, bundled: String?) -> Bool {
        guard let bundled else { return false }
        return adopted != bundled
    }
}
