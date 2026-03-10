Troubleshooting: SMAppService Codesigning Error (-67028)

Summary
- Symptom: `SMAppService` returns status `.notFound` at first, and a subsequent `register()` throws with underlying Security error `errSecCSReqFailed (-67028)`.
- Impact: Helper installation fails; the wizard previously hid the real cause behind a generic “plist not found” error.

What Changed
- Helper registration now proceeds even when `svc.status == .notFound` to surface the true error from `SMAppService`.
- Expected log entries (~/Library/Logs/KeyPath/keypath-debug.log):
  - `⚠️ [HelperManager] Helper status is .notFound - attempting registration anyway to get detailed error`
  - `❌ [HelperManager] Registration failed with detailed error: Error Domain=SMAppServiceErrorDomain Code=3 "Codesigning failure loading plist: com.keypath.helper code: -67028"`

Quick Validation Checklist
- Helper binary exists in the app: `/Applications/KeyPath.app/Contents/Library/HelperTools/KeyPathHelper`
- Helper plist exists in the app: `/Applications/KeyPath.app/Contents/Library/LaunchDaemons/com.keypath.helper.plist`
- `Info.plist` contains `SMPrivilegedExecutables` for `com.keypath.helper` with the correct requirement.
- Helper binary is signed and satisfies the requirement (see Diagnostic Script below).
- App bundle is signed, notarized, and stapled.
- Local machine has a valid Developer ID Application identity (see "Signing Identity Check").

Diagnostic Script
- Run `Scripts/diagnose-helper.sh` (no root required). It prints:
  - App + helper code-signing details and requirements
  - Signature validity for both app and helper
  - Available codesigning identities in the local keychain
  - Extracted `SMPrivilegedExecutables` requirement
  - Requirement check against the helper (`codesign -R <req> <helper>`)
  - Launchctl state summary (best-effort)

Signing Identity Check
- Run: `security find-identity -v -p codesigning`
- If it prints `0 valid identities found`, the helper **cannot** be installed via SMAppService.
  - Install/import the Developer ID Application certificate + private key into the login keychain.
  - Rebuild and re-sign the app bundle, then re-run the diagnostic script.

Hypotheses To Investigate
1) LaunchServices/SM cache confusion or stale state. Try a full system restart after installing the new build.
2) Requirement syntax mismatch. Some OS paths are sensitive to `designated =>` formatting; compare `codesign -d -r- KeyPathHelper` with the requirement string embedded in `Info.plist`.
3) BundleProgram resolution quirk. Confirm `BundleProgram` in `com.keypath.helper.plist` points to `Contents/Library/HelperTools/KeyPathHelper` and that file exists inside the app bundle you’re launching.
4) Timing/race at first launch. Ensure the app is fully launched (not translocated) from `/Applications` before attempting registration.
5) Possible Sequoia regression (macOS 15). If reproducible with a clean system cache and a fresh build, capture the full diagnostics and consider filing a DTS.

Development Caveat
- `Scripts/quick-deploy.sh` should not hot-swap the embedded helper by default.
- Replacing `/Applications/KeyPath.app/Contents/Library/HelperTools/KeyPathHelper` during fast iteration can leave the registered helper in a `spawn failed` state even when `codesign --verify --deep --strict /Applications/KeyPath.app` still passes.
- Symptom:
  - `launchctl print system/com.keypath.helper` shows `job state = spawn failed`
  - `last exit code = 78: EX_CONFIG`
  - helper XPC calls degrade from selector-specific timeouts to a fully unresponsive helper
- If you intentionally deploy a helper change, follow with an explicit helper unregister/register or repair flow from the signed app before trusting XPC diagnostics.

Next Steps
- Reproduce with the updated app and collect the full error details in logs.
- Attach the script output and `BlessDiagnostics` report (from the app’s Diagnostics view) to any DTS report.
