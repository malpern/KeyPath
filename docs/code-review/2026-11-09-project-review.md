# KeyPath project review — 2026-11-09

Reviewed at `master` a20de9c3 (#1391). Four areas: bloat, over-engineering,
macOS best practices, security.

**How this was done.** Static reading and grep only. Nothing was built, run or
connected to. Each area was read by a separate reviewer; the claims in the
"Top recommendations" table and every security finding rated Medium or higher
were then re-checked against the code by hand. Unfixed security findings other
than the already public S1 are tracked privately (see section 1). Items not re-checked, or that
need a running system to confirm, are marked *unconfirmed*. `External/kanata`
was not checked out, so statements about the engine's TCP command set come from
ADR-046 and the Swift client, not the fork's source.

## Status (updated 2026-11-11)

**Overall:** about 55% of the review is done by item count. The top-ranked quick fixes and the deletion pass have shipped. A few small items remain (P4, P5, the CLI link in O8). Most of what is left is the large refactors (O2–O5) and the product decisions. Lines that describe open work are as of 2026-11-11.

Key: ✅ done · 🟡 partly done or waiting on a gate · ⬜ not started · 🔒 tracked privately

### Top recommendations

| # | Item | Status | Where |
|---|---|---|---|
| 1 | ADR-046 (S1) | 🟡 Phases 1–3 and docs shipped: the engine uses a private Unix socket that admits only the app's own PID, and the TCP port is gone. Phase 4, the code-signature check, is in open PR #1416, which also updates ADR-046 to make it a release gate. Until it merges, ADR-046 on master still says phase 4 is not scheduled. | #1412, #1413, #1414, #1416 |
| — | Other security findings | 🔒 Tracked privately | — |
| 2 | Public docs | ✅ Fixed on master and republished to the website, including `getting-started/` and `migration/` | #1394, #1402 |
| 3 | `BehaviorStatePicker` + 15 MB of PNGs | ✅ Deleted | #1398 |
| 4 | Deletion pass (~34k lines) | ✅ Done | #1395, #1397, #1398, #1399, #1406 |
| 5 | Update story | 🟡 Sparkle is re-enabled and passed four update scenarios. One release gate is left: rerun scenarios 1, 2 and 4 on notarized builds with a managed Caps Lock rule active (in progress) | #1409 |
| 6 | Installer collapse (O1) | 🟡 Step 1 merged. Step 2 is written but not yet in a PR | #1410 |
| 7 | `NSAppleEventsUsageDescription` | ✅ Added. Not yet confirmed on a clean VM | #1404 |

### By section

| Item | Status | Notes |
|---|---|---|
| **O1** Installer planner | 🟡 | See row 6 |
| **O2** Four copies of UI state | ⬜ | Large, medium risk |
| **O3** Forwarding layers on the rule path | ⬜ | Falls out of O2 |
| **O4** Wizard module boundary | ⬜ | After O1 |
| **O5** Events, health polling, stacked caches | ⬜ | Dead `EventRouter` chain removed in #1406; the typed event hub, polling and caches remain |
| **O6** Plugin system | ✅ | Downloads removed (#1407); Insights linked into the app (#1411) |
| **O7** Metal stage, onboarding, packs, CLI split | ⬜ | Product decisions not made |
| **O8** Unimplemented flags, wording, public-docs lint | ✅ | #1405 |
| **O8** Leftover `/usr/local/bin/keypath-cli` link on uninstall | 🟡 | Documented, not fixed |
| **O8** `TestEnvironment` in production, singletons vs `ServiceContainer`, retiring finished lint tests | ⬜ | |
| **B1** Dead view and images | ✅ | #1398 |
| **B2** Scripts | ✅ | #1395 |
| **B3** Dead Swift | ✅ | #1398, #1406. The function-level Periphery pass has not run |
| **B4** Tests for removed behaviour | 🟡 | Dead tests removed. Refreshing two stale snapshot references is written but not yet in a PR. `Tests/Experiments` is kept, because two scripts compile it |
| **B5** Binary assets | 🟡 | Unused assets deleted (#1397). Not done: recompressing `images/help` (60 MB), removing its duplicates in app resources, rendering Metal snapshots at a smaller scale |
| **B6** Root and package stragglers | 🟡 | Root files deleted (#1395). Not done: folding `KeyPathSystemProbes` into `KeyPathCore`, the nine unused library products, the wizard's unused screenshot |
| **B7** Docs | 🟡 | Public pages fixed and published; `docs/archive` deleted (#1399). `KEYPATH_USE_INSTALLER_ENGINE` removed from `AGENTS.md`, the wizard smoke checklist and the reliability-matrix script (this change). Not done: rewrite `runtime-architecture.html` (marked out of date), recapture the macOS 27 Accessibility screenshot |
| **P1** Sparkle | 🟡 | See row 5 |
| **P2** Apple Events usage string | ✅ | #1404 |
| **P3** Blocking subprocesses | ✅ | #1404: `SecCodeCopySelf` instead of `codesign`, and pipes drained before waiting. `ps` is kept for the wizard's migration page |
| **P4** Shell-outs with API replacements | ⬜ | `mdfind`, `defaults`, `chflags`, `open -t`, `/bin/kill` |
| **P5** `os.Logger` in `AppLogger` | ⬜ | |
| **P6** Concurrency leftovers | ⬜ | `@unchecked Sendable`, `NSLock` → `Mutex`, `asyncAfter`, default main-actor isolation |
| **P7** Liquid Glass | ✅ | System glass in `AppGlassBackground` (#1408). Checked on screen over busy and plain backgrounds, light and dark |
| **P7** Other idioms | ⬜ | 668 `.foregroundColor`, 20 `activate(ignoringOtherApps:)`, 6 `lockFocus()`, `NSViewRepresentable` wrappers, plain `Window` scenes |
| **P8** Localization | ⬜ | Decision needed |
| **P9** Test isolation | ⬜ | |

### Also done since the review (not in its list)

- ADR-048 keyboard attribution: spike, matcher and the log-only matcher in the session worker (#1392, #1393, #1396, #1400, #1401)
- The CLI's engine commands are answered by the app (#1388, #1413); tests for that path are in open PR #1415

### Next, in order

1. Merge #1415, then #1416 (the phase 4 release gate)
2. Finish the Caps Lock gate for Sparkle (P1)
3. Open PRs for the snapshot refresh, then installer step 2
4. Run the clean-VM install test (also confirms P2)
5. The large refactors: O2/O3, then O4, then O5

---

## Summary

The core is in good shape. The session runtime, the journaled config write, the
permission oracle and the signing posture are careful work, and the retired
privileged stack is almost entirely gone from `Sources`. The language-level
modernisation is done: Swift 6 mode on every target, full `@Observable`
migration, no dead availability checks.

The problems are around the core:

- **Security.** The engine's control port is unauthenticated (already tracked
  as #1354 / ADR-046). Other unfixed findings are tracked privately and are
  not described here.
- **Over-engineering.** The installer's plan/recipe/state-matrix machinery now
  encodes a single `if`. UI state is copied through four layers by hand.
- **Bloat.** About 34,000 lines of scripts, docs, tests and dead Swift can be
  deleted with low risk, plus about 30 MB of binary assets, 15 MB of which
  ships inside the app for a view that is never shown.
- **Public docs were wrong.** `PRIVACY.md`, `SECURITY.md`, `CONTRIBUTING.md` and
  `getting-started/installation.md` described Input Monitoring, Full Disk
  Access and the privileged helper as current. They are corrected in the same
  change as this review, but the published website (`gh-pages`) still carries
  the old pages; see B7.

## Top recommendations

| # | Recommendation | Area | Effort | Why now |
|---|---|---|---|---|
| 1 | Land ADR-046, together with the privately tracked security fixes | Security | L | Any local process can read keystrokes and inject input |
| 2 | Rewrite `PRIVACY.md`, `SECURITY.md`, `CONTRIBUTING.md`, `getting-started/installation.md` | Docs | S | Public, and contradicted the shipped product; master is fixed, the website is not |
| 3 | Delete the dead `BehaviorStatePicker` view and its 15 MB of bundled PNGs | Bloat | S | Shrinks the shipped app |
| 4 | Deletion pass: `Scripts/archive`, `Scripts/test-scripts`, dead Swift, dead tests, `docs/archive` | Bloat | S | ~34k lines, low risk, makes everything after it easier |
| 5 | Decide the update story: re-enable Sparkle or add a version check | Platform | M | The app ships Sparkle but never checks for updates |
| 6 | Collapse `InstallerEngine` planning to inspect / start-and-verify / uninstall | Over-eng. | M | Scaffolding for a stack that no longer exists |
| 7 | Add `NSAppleEventsUsageDescription` | Platform | S | AppleScript actions may be silently denied (*unconfirmed*) |

---

## 1. Security

Threat model: another process running as the same user without Accessibility;
a web page or document invoking `keypath://`; a malicious config or import;
the update and build supply chain; leakage of typed text.

Some exposure is inherent to any remapper: an unsandboxed process that holds
Accessibility and sees every key, and a user-editable config that defines
macros. The findings below are the parts that can be fixed.

### S1. Engine control port has no authentication — High (tracked: #1354, ADR-046)

> **Since this review:** ADR-046 is Accepted and phases 1–3 have shipped. The TCP port is gone; see Status above. The text below describes the code as reviewed.

`127.0.0.1:37001` is fixed and unauthenticated. The code's own comment at
`Sources/KeyPathAppKit/Services/Networking/KanataTCPClient.swift:59-71` says
any local process, including other users' processes and sandboxed apps with
network-client, can receive every `KeyInput` event and the config text, press
virtual keys, move the mouse and load any readable file as the config.

ADR-046 describes the attack scenarios. One documentation item to add: correct
`docs/adr/adr-013` and any user-facing text that says the port only handles
config reloads.

**Fix:** ADR-046 options C and A together. This should block the first
session-runtime release.

### Further findings, reported privately

Other security findings from this review are not described in this public
document, following [`SECURITY.md`](../../SECURITY.md). They are tracked
privately and will be published once fixed. Plan the ADR-046 change with
them in view.

### Already done well

- The engine is built without kanata's `cmd` feature, so no config can run
  shell commands in the engine.
- Hardened runtime on every component with **no** exception entitlements.
- Sparkle feed is HTTPS, EdDSA-signed, verified before extraction.
- The worker refuses to run as root and exits on Secure Input.
- Insights data is AES-GCM encrypted with a Keychain key; the Anthropic API
  key is in the Keychain.
- No analytics or crash-reporting SDK. No TCC database access. No secrets in
  the repository.
- `Package.resolved` and `Cargo.lock` are committed.
- ADR-046 is itself a candid and largely correct threat model.

---

## 2. Over-engineering

### O1. The installer planner encodes one `if`

`InstallerEngine.swift` (762 lines), `InstallerEngineTypes.swift` (500),
`InstallerStateMatrix.swift`, `InstallerDecisionPipeline.swift` and
`InstallerEngine+Recipes.swift` were built to order helper, daemon and driver
steps. What is left:

- `AutoFixAction` has two cases (`WizardTypes.swift:153-158`); one is never
  planned.
- Install and repair both reduce to `isReady ? [] : [.restartCommServer]`.
- The state matrix has two rows and one action.
- `orderRecipes` returns its input. `actionNeedsPrompt` and
  `requiresManualApproval` return `false`. Two report states are unreachable.

Net behaviour of repair: if the runtime is not ready, start it and re-check.

**Recommendation:** collapse to `inspect()`, `startAndVerify()` and
`uninstall()`. Keep the transaction gate and the fresh re-capture before
reporting success; those are the valuable parts. Keep the CLI's JSON field
names stable. About 4.5k lines of tests pin the current shapes, so this is a
deliberate PR, in the spirit of the ADR-047 exception.

### O2. One UI state, four copies

`RuleCollectionsManager` owns the state. `RuntimeCoordinator` mirrors it,
builds a `KanataUIState` snapshot, `StatePublisherService` pushes it down a
single-subscriber `AsyncStream`, and `KanataViewModel.updateUI` copies about
20 fields. There are 69 manual `notifyStateChanged()` calls. Of
`KanataViewModel`'s 47 methods, 33 are one-line forwards, and the
`underlyingManager` escape hatch is used 65 times, so the layer isolates
nothing. `MainAppStateController` holds a third copy of health state.

The codebase already uses `@Observable` in 59 places.

**Recommendation:** make the owner observable, delete `KanataUIState` and
`StatePublisherService`, shrink `KanataViewModel` to dialog and toast state.
`AGENTS.md` says `RuntimeCoordinator` is "not an `ObservableObject`"; revisit
that line. Large, medium risk.

### O3. Forwarding layers on the rule path

Toggling a rule passes through about 15 calls. `RuleCollectionsCoordinator`
(274 lines) and `RuntimeCoordinator+RuleCollections` (170) only log and
forward. The reload result is re-wrapped five times
(`TCPReloadResult → EngineReloadResult → TCPReloadResult → ReloadResult →
SaveResult → Bool`). `ConfigReloadCoordinator` takes 20 injected closures and
has three parallel test seams for one reload call.

**Recommendation:** delete the two forwarding files (falls out of O2; ADR-043
sanctions it). In `ConfigReloadCoordinator`, drop `EngineClient` (one
conformer) and keep one seam. Leave its Caps restart logic alone.

### O4. The wizard module boundary

The wizard was split out for incremental compilation. The cost is
`WizardDependencies`, a static container of ten mutable globals, five
protocols that exist only to cross the boundary, and a `WizardRuntimeStatus`
that copies `RuntimeStatus` case for case. Three wizard pages still live in
AppKit. The wizard now has two real steps across about 10.7k lines.

**Recommendation:** after O1, either fold the wizard back into AppKit or keep
the module for views only.

### O5. Events and health: untyped bus, polling, stacked caches

- Kanata events arrive typed, are repacked as `[String: Any]`, posted through
  `NotificationCenter` per keystroke, and parsed again by observers
  (`RuleCollectionsManager+EventMonitoring.swift`). The rule-storage manager
  owns the TCP listener. There are about 80 notification names in total.
- `MainAppStateController.subscribeToServiceHealth` (`:214`) polls every two
  seconds although `ServiceLifecycleCoordinator.onStateChanged` exists.
- A permission answer passes three cache-and-dedup layers (Oracle, validator,
  state controller). The validator's snapshot is about 20 lines of work
  wrapped in a TTL cache and a 90-line timeout race.
- Four separate timeout helpers with four error types.

**Recommendation:** a small typed event hub owned by the lifecycle side; drive
revalidation from `onStateChanged`; keep only the Oracle's cache; one timeout
helper in `KeyPathCore`.

### O6. Plugin system for one first-party plugin

`PluginManager` (469 lines), a downloader, a catalog card, an `@objc` protocol
and a dynamic-library product exist to load `KeyPathInsights` (1,792 lines).
Loading downloaded code is also a trust surface.

**Recommendation:** compile Insights in behind a preference, or ship it only
inside the app bundle and drop the downloader. Product decision.

### O7. Footprint worth a product decision

| Feature | Size | Note |
|---|---|---|
| Metal keyboard stage | 6,022 lines Swift + 1,190-line shader + build plugin | Used only by the first-run screen; a SwiftUI fallback already exists, so every scene is maintained twice |
| First-success onboarding | 3,549 lines | |
| Packs | ~8,000 lines (services, gallery, facade) | A second catalog over rule collections, all hardcoded in Swift. If packs will never be distributed, presets would do |
| `keypath-cli` | imports AppKit in 57 files | Links SwiftUI and the Metal renderer. A `KeyPathEngine` target (config, rules, session runtime, networking) would be the split that pays |

The Karabiner converter, QMK import and layout tracer are proportionate.

### O8. Smaller items

- Nothing guards the public docs against drifting back to the retired
  stack. A lint that fails when `README.md`, `PRIVACY.md`, `guides/`,
  `getting-started/` or `docs.md` describe Input Monitoring, Full Disk
  Access, a privileged helper or a LaunchDaemon as current would be cheap.
- Uninstall leaves the root-owned `/usr/local/bin/keypath-cli` link behind;
  `SessionUninstallCoordinator` never references it. The docs now say so;
  the cleaner fix is to install the link somewhere user-writable.

- Two feature flags marked "NOT YET IMPLEMENTED"
  (`FeatureFlags.swift:223-242`) are consulted in three places; `PermissionGate`
  exists only behind one. Delete.
- `TestEnvironment.*` is checked in production code 56 times.
- 90 `static let shared` singletons coexist with a half-adopted
  `ServiceContainer`. Pick one.
- User-visible strings still say "Restart Service with Authentication";
  `restartCommServer` means "start the session runtime".
- 36 source-grepping lint tests (3,394 lines). Several guard the retired
  stack or are finished migration ratchets (`W6DeletionPassLintTests`). They
  pin file paths and make every cleanup above noisier. Retire the finished
  ones.

### Leave alone

- `RecoverableRuleWrite` and `ConfigurationOperationGate`: a journaled
  multi-file write with a cross-process lock. Earned, because the CLI is a
  second writer.
- The session runtime worker, lifecycle and `SessionCaps*`. Dense, but each
  piece answers a specific incident or OS limit.
- `PermissionOracle`.
- `KeyPathRulesCore` and the pure decision functions (`WizardRouter`,
  `SystemInspector`).
- `release-doctor`, `verify-installed-app`, `review-gate`.

---

## 3. Bloat

Verified deletable: about 34,000 lines of text and 30 MB of binaries.
Suspected on top: about 30,000 lines, and 45–50 MB from recompressing images.

### B1. Dead view with 15 MB of bundled images

`BehaviorStatePicker` and its cell views
(`Sources/KeyPathAppKit/UI/Overlay/BehaviorStatePicker.swift`, 413 lines) are
never instantiated. They are the only loader for
`Resources/BehaviorIcons/`: twelve 2048×2048 PNGs, 15 MB, shipped in the app.
Keep `enum BehaviorSlot`, delete the rest. Its `imageName` and
`selectedImageName` properties live in the same file and name the PNGs, so
drop them with the assets.

### B2. Scripts

`Scripts/` holds 293 tracked files.

| What | Size | Status |
|---|---|---|
| `Scripts/archive/` | 57 files, 4,584 lines | Retired-stack; nothing references it |
| `Scripts/test-scripts/`, `test-fixtures/` | 51 files, ~2,900 lines | Scratch files; check one fixture used by `build-kanata-host-bridge.sh` |
| Keyboard image slicing one-offs | 13 Python files, ~2,450 lines | Five generations of the same script |
| `Scripts/ui-tests/` | 19 files, 2,595 lines | Peekaboo suites nothing invokes |
| Other unreferenced scripts | ~1,500 lines clear, ~3,500 docs-only | `test-installer.sh` and `test-hot-reload.sh` test the LaunchDaemon |

The `qa-*-smoke.sh` scripts may be manual release tools; confirm before
deleting.

### B3. Dead Swift

About 3,900 lines of views and files with no references, including
`AboutView.swift` (638; the menu uses the standard About panel),
`WindowResizeHandle.swift` (372), `ActiveRulesView.swift` (363),
`AIKeyRequiredDialog.swift` (348), `KeyPathCLI/Utilities/UpdateChecker.swift`
(no callers) and `KanataBehaviorParser.swift` (255,
tests only). Also, with zero production callers:

- `StartupCoordinator` (never started)
- `EventRouter`, `DefaultEventProcessor`, `EventProcessing` (~570 lines;
  `setEventRouter` is only ever passed `nil`)
- most of `ServiceHealthMonitor` (495 lines; restart cooldown and crash-loop
  logic kept alive by a 419-line test file)
- the `launchctl` probe chain in `KeyPathSystemProbes` and `SystemStateProvider`
- about 20 VirtualHID and legacy-path members of `WizardSystemPaths.swift`
- nine notification names with no post and no observer

A name-based scan suggests another 1,500–2,500 lines at function level.
Run Periphery for that layer rather than trusting grep.

### B4. Tests for removed behaviour

About 1,300 lines verified: tests for `ServiceHealthMonitor`'s dead paths,
`KanataBehaviorParser`, `TransientStartupWindowEvaluator`,
`SafetyTimeoutService`, `WordlistStore`, `WizardTelemetry`. Also:

- `Tests/Experiments/` (899 lines) is in no package target.
- Six `*.actual.kbd` files are committed test output; add to `.gitignore`.
- Three snapshot references have no matching test; two are byte-identical.

### B5. Binary assets

| What | Size | Action |
|---|---|---|
| `images/help/` | 60 MB | Headers are 1–7 MB PNGs; recompress. 36 files (7.5 MB) are byte-duplicated in `Sources/…/Resources`; copy at build time. 12 are unreferenced |
| `dev-tools/dmg/` | 16 MB | ~12 MB are rejected design iterations |
| Snapshot references | 19 MB | Five Metal frames account for 8.6 MB; render at lower scale |
| `Resources/BehaviorIcons` | 15 MB | Delete (B1) |

One 153 KB screenshot is committed six times under three names; the wrong
image was probably copied over three slots.

### B6. Root and package stragglers

- Delete: `test.sh`, root `build-and-sign.sh` shim, `default.profraw`,
  `.watchman-cookie-…`, `design-qa.md`, `ScrollTest/`,
  `External/.github`, `External/.devcontainer`.
- `KeyPathSystemProbes` (one file, one importer): fold into `KeyPathCore`.
- Nine library products nothing outside the package consumes (*unconfirmed*
  that no build script names them).
- The wizard target's only resource is an unreferenced Karabiner driver
  screenshot.

### B7. Docs

`docs/` is 418 files and about 61,600 lines. Roughly 55–65% is historical
record (an estimate from directory purpose, not a file-by-file read):
`archive` (13k lines), `bugs`, `planning`, `analysis`, `code-review`, half of
`testing`.

**Wrong and public — fixed on master in the same change as this review:**

- `PRIVACY.md:20,38` says Input Monitoring is required and asks for Full Disk
  Access. `guides/privacy.md` says the opposite.
- `SECURITY.md:41` says KeyPath "includes privileged helper and LaunchDaemon
  flows".
- `CONTRIBUTING.md:101` says Kanata starts as a LaunchDaemon.
- `getting-started/installation.md:50` documents "Step 1: Privileged Helper
  Installation" and asks for an admin password.
- `migration/karabiner-users.md` said KeyPath uses the Karabiner VirtualHID
  driver; `migration/kanata-users.md` said setup asks for Input Monitoring,
  installs that driver and configures a LaunchDaemon.
- `README.md` said "No kernel extensions — uses Apple's modern driver
  framework" and "works completely offline".

**The website still shows the old pages.** The site is served from the
`gh-pages` branch, which keeps its own copies. There,
`getting-started/installation.md` and `guides/privacy.md` still describe the
privileged helper, Input Monitoring and Full Disk Access, although master's
`guides/privacy.md` is already correct. `Scripts/publish-guides.sh` publishes
only `guides/`, `docs.md`, `images/help/` and `offline-help/`, so
`getting-started/` and `migration/` have no publishing path at all. Run the publish script, and
either extend it to `getting-started/` and `migration/` or stop keeping a master copy that
cannot be published.

**Stale developer docs:** `docs/architecture/xpc-architecture.html`,
`runtime-architecture.html`, `docs/troubleshooting/debugging-kanata.md`,
`docs/guides/kanata-macos-setup-guide.md`,
`docs/process/new-developer-guide.md`, `docs/KEYPATH_GUIDE.adoc`.

`AGENTS.md`, `CONTRIBUTING.md`, `.swiftlint.yml` and
`docs/testing/accessibility-enforcement.md` cited
`ACCESSIBILITY_COVERAGE.md`, which was archived earlier (0e8d6c59); the
citations are removed in this change. `AGENTS.md` still names
`KEYPATH_USE_INSTALLER_ENGINE`, which looks vestigial.

`docs.md`, which is published, linked "Privileged Helper & XPC"
(`xpc-architecture.html`); the link is removed in this change. The
"Runtime & Service Lifecycle" page it also links is stale and needs a
rewrite.

**Recommendation:** delete `docs/archive`; git history is the archive. Stop
committing generated dashboards.

---

## 4. macOS best practices

Platform guidance below is from general knowledge of current Apple practice
and was not checked against the macOS 27 SDK. Nothing was compiled, so
deprecation-warning counts are not measured; a `swift build` would turn
several of these from recalled to confirmed.

### Already current

- Swift 6 language mode on every target, tests included.
- Observation fully migrated: 59 `@Observable`, zero `ObservableObject` or
  `@Published`.
- Zero `#available` checks; no `NavigationView`, no old alert APIs.
- Launch at login through `SMAppService.mainApp` behind an off-main provider.
- App Intents, `UNUserNotificationCenter`, `NSWorkspace.OpenConfiguration`.
- Hardened runtime, no exceptions; private CGS symbols bound by `dlsym` with a
  fallback.
- Accessibility identifiers: `check-accessibility.py` passes on 381 files.
- The AppKit window management for overlay, HUD and palette panels is
  justified; SwiftUI scenes do not express non-activating multi-Space panels.

### P1. Sparkle is configured as automatic and disabled in code — do now

`Info.plist` sets `SUEnableAutomaticChecks` and `SUAutomaticallyUpdate`.
`UpdateService.usesManualDownloads`
(`Sources/KeyPathAppKit/Services/UpdateService.swift:93`) is hardcoded `true`,
so the updater is never constructed and "check for updates" opens the GitHub
releases page. The app embeds and signs Sparkle but has no update check. For
software that sees every keystroke, users not learning about a security fix
is a real cost.

**Recommendation:** finish qualifying updater shutdown and re-enable Sparkle,
or add a lightweight "new version available" notice. Host the appcast on
Pages or Releases, not a raw branch file.

### P2. Apple Events entitlement with no usage string — do now

`KeyPath.entitlements` declares `automation.apple-events`. The only usage
string in `Info.plist` is `NSAccessibilityUsageDescription`, which macOS does
not read. Apple Events are sent from `ActionDispatcher.swift:855,875,959` and
`WizardWindowManager.swift:69,106`. Without `NSAppleEventsUsageDescription`
the consent prompt may not appear and sends are denied (*unconfirmed*; test on
a clean VM). The wizard's "quit System Settings" could use
`NSRunningApplication.terminate()` and need no consent.

### P3. Blocking subprocesses on the main actor — do now for the launch path

- `WizardSignatureHealthCheck.isRunningAdHoc()`
  (`KeyPathWizardCore/WizardServiceProtocols.swift:103-113`) runs
  `codesign -dvvv` synchronously at launch. Use `SecCodeCopySelf` and
  `SecCodeCopySigningInformation`.
- `detectRunningKanataProcess()` runs `ps` synchronously; the repo already
  reads the process table directly in `SessionWorkerSweep.swift:138`.
- `ExternalKanataService.swift:148-159` waits for exit before reading the
  pipes, which can deadlock on large output.

### P4. Other shell-outs with direct API replacements

`mdfind` → `NSMetadataQuery`; `defaults` → `UserDefaults(suiteName:)`;
`chflags` → `URLResourceValues.isHidden`; `open -t` → `NSWorkspace`;
`/bin/kill` → `kill(2)`. `hidutil`, `tccutil` and `ditto` have no good
replacement; keep. `ExternalKanataService` still calls `launchctl unload`,
which contradicts the `AGENTS.md` rule; either note the exception there or
move to `bootout`.

### P5. Logging is a custom file logger only

1,824 `AppLogger` calls, one `os.Logger`. The file log is useful for user
diagnostics and QA scripts. Make `AppLogger` also emit to `os.Logger` with a
subsystem and category; no call sites change. That gives Console filtering
and, later, privacy annotations for anything that could reveal typed keys.

### P6. Concurrency leftovers

- Five blanket `@unchecked Sendable` extensions on large types:
  `RuntimeCoordinator`, `SystemValidator`, `PermissionRequestService`,
  `FeatureFlags`, `AppLogger`. These are where a real data race would hide.
- 25 `NSLock`, zero `Mutex`. `Mutex<State>` makes lock-protected state checked
  `Sendable`.
- Unsynchronised static caches reachable off the main actor, for example
  `AppIconResolver.swift:10` and `FeatureFlags.swift:59`.
- 68 `DispatchQueue.main.asyncAfter` and 25 `Timer.scheduledTimer` in UI
  code; these are not cancellable. Use `Task.sleep` or `.task(id:)`.
- `swift-tools-version` is 6.1. Default main-actor isolation on the UI targets
  (Swift 6.2) would remove much of the 779 `@MainActor` and 127
  `MainActor.run` (*unconfirmed* against the Xcode 27 toolchain). Try it on a
  leaf UI target first.

### P7. SwiftUI and AppKit idioms — opportunistic

- `.foregroundColor`: 758 uses against 867 `.foregroundStyle`. Half migrated;
  one codemod PR checked by snapshots.
- No Liquid Glass in the main app. `AppGlass.swift` imitates it with
  `NSVisualEffectView` and hand-drawn gradients. Since every surface routes
  through `AppGlassBackground` and the floor is macOS 27, swapping the
  implementation is contained. At minimum, merge the three duplicate
  `VisualEffectBlur` wrappers.
- Deprecated since macOS 14, likely compiler warnings today:
  `NSApp.activate(ignoringOtherApps:)` (22 uses; the replacement behaves
  differently, test first), `NSImage.lockFocus()` (3), `Process.launchPath` (1).
- About a third of the 21 `NSViewRepresentable` wrappers have SwiftUI
  replacements (`@FocusState`, `.onContinuousHover`, `WindowDragGesture`).
- Help, Simulator, Recent Keypresses and About windows could be plain `Window`
  scenes.

### P8. Localization needs a decision

One String Catalog (433 keys, English and Japanese) against 764 literal
`Text("…")` call sites, and no catalog in the wizard, Insights or tracer
targets. With SwiftPM there is no extraction step, so the catalog drifts.
Either commit to localization (add a lint for literals and bundle routing) or
stop carrying partial Japanese.

### P9. Tests

4,651 XCTest methods and 851 Swift Testing tests. New tests are already going
to Swift Testing; do not mass-convert. The real blocker is that tests share
on-disk state (the CI workflow serialises jobs because of it). Fix isolation
before adopting more in-process parallel testing.

---

## Suggested order

1. **Public docs** (B7 "fix first"). Hours.
2. **Deletion pass** (B1–B6, O8, dead code from O5). Low risk, and it removes
   tests and lint ratchets that would otherwise fight the later steps. Split
   by directory so each PR is easy to review.
3. **Security before the first session-runtime release:** S1 and the
   privately tracked findings together, since they share a threat model and a
   design.
4. **Platform quick fixes:** P1 decision, P2, P3 launch path, the three
   deprecated APIs in P7.
5. **Installer collapse** (O1), then **state ownership** (O2, O3), then the
   wizard boundary (O4) and events (O5).
6. **Product decisions**, in no fixed order: plugin system (O6), Metal
   stage, packs, localization, Liquid Glass.

## Not verified

- The engine's TCP command set (submodule not checked out).
- `images/help/screenshot-accessibility-settings.png` shows the pre-27
  Accessibility pane; the install guide's caption now names the macOS 27
  pane. Recapture it on macOS 27.
- The usage-string behaviour in P2, and parts of the privately tracked
  findings. Each needs a clean lab VM.
- Deprecation status of specific APIs in the macOS 27 SDK.
- The function-level dead-code estimate and the historical share of `docs/`.
- Build-time effects of any target change.
