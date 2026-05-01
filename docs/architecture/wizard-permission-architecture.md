# Wizard Permission Architecture: History, Issues, and Reunification

## How It Used to Work

Before Mode B, the permission system was simple:

1. **PermissionOracle** checked TCC for `kanata-launcher` — the one binary that ran
2. The wizard showed permissions as granted/denied based on Oracle results
3. The daemon either started or didn't — one error path, one classification

There was one binary, one TCC identity, one error message, and one detection path.

## How It Drifted

Mode B introduced `Kanata Engine.app` as a wrapper around the kanata binary, with its own bundle ID (`com.keypath.kanata-engine`). This created a second TCC identity. The Oracle was updated to check the bundle ID first, with a path-based fallback. The wizard was updated to reveal `Kanata Engine.app` in Finder.

When Mode B was reverted to Mode A, the Oracle, wizard text, and Finder reveal were patched to point back at `kanata-launcher`, but the patches were incremental — each fix addressed one symptom without seeing the full picture. Meanwhile, a second stderr-parsing path (`checkKanataInputCaptureStatus`) had been added independently to detect a specific runtime failure ("cannot open built-in keyboard"), and it was classified as an Input Monitoring issue rather than an Accessibility issue.

The result: three independent detection paths, each reading the same daemon stderr log for overlapping error patterns, each classifying the same root cause under different issue identifiers.

## The Three Detection Paths Today

### Path 1: PermissionOracle (TCC database)

**What it checks:** Reads TCC database for `kanata-launcher` path entries.

**What it reports:** Per-permission status (`.granted`, `.denied`, `.unknown`) for Accessibility and Input Monitoring.

**Limitation:** TCC can be stale after a rebuild (code signature changes but TCC still says "granted"). The Oracle can't distinguish "genuinely granted" from "stale grant that macOS will reject at runtime."

### Path 2: SystemValidator.checkDaemonStderrForPermissionFailure()

**What it checks:** Reads the tail of `/var/log/com.keypath.kanata.stderr.log` for:
- `"kanata needs macOS Accessibility permission"` (startup failure — kanata can't start at all)
- `"IOHIDDeviceOpen error"` + `"not permitted"` (runtime failure — kanata started but can't grab a device)

**What it reports:** `kanataPermissionRejected: Bool` on `HealthStatus`. When true, the wizard routes to the Accessibility page and suppresses the input capture false-positive.

**History:** Added during the Mode A revert to detect stale TCC grants. Originally gated on `!kanataRunning` (only checked when daemon wasn't running). Fixed to check unconditionally when we discovered kanata CAN run with IM granted but AX denied.

### Path 3: ServiceHealthChecker.checkKanataInputCaptureStatus()

**What it checks:** Reads the SAME stderr log for:
- `"iohiddeviceopen error"` + `"not permitted"` + `"apple internal keyboard / trackpad"`

**What it reports:** `kanataInputCaptureReady: Bool` + `kanataInputCaptureIssue: String?` on `HealthStatus`. When false, the SystemContextAdapter generates a `.permission(.kanataInputMonitoring)` issue titled "KeyPath Runtime Cannot Open Built-In Keyboard."

**The problem:** This is the SAME root cause as Path 2 (Accessibility denial) but classified as Input Monitoring. When IM is granted and AX is denied, the summary shows both Input Monitoring (from this path) and Accessibility (from Path 2) as broken — but only AX is actually missing.

**Current mitigation:** When `permissionRejected` is true, `effectiveInputCaptureReady` is forced to true. But this only works when Path 2 detects the issue first, which requires matching the right stderr string.

## Why Issues Keep Slipping In

The fundamental problem: **three parsers independently read the same log file, match overlapping but inconsistent patterns, and feed results into different parts of the issue classification system.** Any change to one parser (adding a new pattern, changing the gate condition) can create a mismatch with the others.

Specific failure modes we hit:

1. **String mismatch:** Path 2 checked for `"kanata needs macOS Accessibility permission"` (startup failure message). Path 3 checked for `"IOHIDDeviceOpen error"` (runtime failure message). Same root cause, different error strings, different code paths.

2. **Gate condition mismatch:** Path 2 was gated on `!kanataRunning`. But kanata CAN run (TCP responsive) while AX is denied — it just can't grab the keyboard. Path 3 had no such gate. Result: Path 3 fired (input capture not ready) but Path 2 didn't (kanata is running), so the suppression didn't kick in.

3. **Classification mismatch:** Path 3 tags its issue as `.kanataInputMonitoring`. The summary page groups issues by permission type. An AX denial showing up as an IM issue means the IM page shows red even when IM is granted.

4. **TCC path mismatch:** The staging folder hard-link approach created TCC entries under a different path than the Oracle checked. The Oracle reported `.unknown`, the wizard showed "not verified," and the user went in circles.

## Proposal: Reunify into One Detection Path

### The unified function

Replace all three stderr-parsing paths with a single function:

```swift
struct KanataDaemonDiagnosis {
    enum PermissionStatus {
        case allGranted
        case accessibilityDenied(detail: String)
        case inputMonitoringDenied(detail: String)
        case unknown
    }
    
    let permissionStatus: PermissionStatus
    let canCaptureBuiltInKeyboard: Bool
}

static func diagnoseDaemonStderr() -> KanataDaemonDiagnosis {
    // Read stderr ONCE
    // Classify ALL known error patterns
    // Return a single structured result
}
```

### What it replaces

| Current | Replaced by |
|---------|-------------|
| `SystemValidator.checkDaemonStderrForPermissionFailure()` | `diagnoseDaemonStderr().permissionStatus` |
| `ServiceHealthChecker.checkKanataInputCaptureStatus()` | `diagnoseDaemonStderr().canCaptureBuiltInKeyboard` |
| The `effectiveInputCaptureReady` suppression logic | Unnecessary — the unified function classifies correctly the first time |

### Where it lives

In `SystemValidator` or a new `KanataDaemonDiagnostics` type. The key constraint: it must be called ONCE per validation cycle and the result passed through, not called independently by multiple consumers who each parse the log their own way.

### How the issue pipeline changes

```
Before:
  Oracle (TCC) ──→ PermissionSnapshot ──→ SystemContextAdapter ──→ Issues
  checkDaemonStderrForPermissionFailure() ──→ permissionRejected ──→ Issues
  checkKanataInputCaptureStatus() ──→ inputCaptureReady ──→ Issues
  (Three inputs, overlapping classification, suppression hacks)

After:
  Oracle (TCC) ──→ PermissionSnapshot ──→ SystemContextAdapter ──→ Issues
  diagnoseDaemonStderr() ──→ KanataDaemonDiagnosis ──→ HealthStatus ──→ Issues
  (Two inputs, no overlap, no suppression needed)
```

### Implementation order

1. Create `KanataDaemonDiagnosis` struct and `diagnoseDaemonStderr()` function
2. Wire it into `SystemValidator.checkHealth()` replacing both stderr checks
3. Update `HealthStatus` to carry the diagnosis instead of separate booleans
4. Remove `checkKanataInputCaptureStatus()` from `ServiceHealthChecker`
5. Remove the `effectiveInputCaptureReady` suppression logic
6. Update `SystemContextAdapter` to use the unified diagnosis for issue classification
7. Add tests that verify: AX denied → only AX issues (not IM), IM denied → only IM issues, both denied → both issues

### CLAUDE.md rule to add

```
### Permission Detection
- ❌ Don't parse daemon stderr independently — use `diagnoseDaemonStderr()` as the single source of truth
- ❌ Don't classify IOHIDDeviceOpen errors as Input Monitoring — they indicate Accessibility denial
```
