# Deferred Mac App Store feasibility

Decision: 2026-10-06. Continue toward a signed, notarized direct-download release.
App Store support is a separate future investigation, not a production blocker
and not a reason to redesign the current runtime now.

Removing the driver, privileged installation, Full Disk Access and browser-history
import simplifies setup. It does not establish App Store eligibility. The current
app disables App Sandbox and uses an active event tap plus generated keyboard
events. Input Monitoring can support sandboxed observation; that alone does not
prove suppress-and-replace remapping works or would be accepted by review.

## Bounded future gate

1. Build a minimal sandboxed prototype and test one real key remap on a clean VM:
   original event suppressed, replacement delivered, normal key-up/repeat and
   quit behavior, with ordinary user consent. Do not rewrite KeyPath first.
2. If that works, separately evaluate Caps→F18 device mapping and supported
   recovery under sandboxing. Preserve the distinction between technical
   capability and App Review approval; seek Apple guidance on the actual APIs.
3. Only after a viable core path is established, estimate an App Store edition:
   sandbox-compatible configuration/file/script access, bundled workers and
   lifecycle, and App Store updates in place of Sparkle. No external helper may
   be used to evade the sandbox requirement.
4. Stop if core remapping needs an unsupported exception or unacceptable feature
   loss. Keep the direct-download product intact. Record evidence before funding
   a larger migration.

No sandbox experiment or Apple submission has been performed for this gate.
No App Store approval is promised.

## Sources checked October 6, 2026

- [Apple App Review Guidelines, 2.4.5](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility): sandboxing, packaging, privilege and update requirements.
- [Apple DTS on sandboxed keyboard observation](https://developer.apple.com/forums/thread/811443): event taps with Input Monitoring, and testing on a clean machine. This discusses observation, not acceptance of KeyPath's full remapper.
- Current implementation: `KeyPath.entitlements`, `SessionRuntimeWorker.swift`,
  `SessionCapsHIDUtilTransport.swift` and `UpdateService.swift`.
