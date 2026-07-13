# CODE_AUDIT.md — KeyPath

**Date:** 2026-05-21
**Scope:** macOS keyboard remapping app (SwiftUI + Kanata backend, LaunchDaemon/PrivilegedHelper)
**Codebase:** ~169K LOC across 807 Swift files (Sources/), Swift 6.1, macOS 15+
**Build warnings:** 0 (even with `-strict-concurrency=complete`)

---

## 1. Executive summary

1. ~~**[Critical] Shell command injection in AppleScript directory preparation** — §5.1~~ ✅ Fixed
2. ~~**[Critical] Path traversal in VHID driver installation** — §6.1~~ ✅ Fixed
3. ~~**[High] Hanging continuations without timeouts** — §3.1~~ ✅ Fixed (cancellation handler added; ConfigurationService continuations verified safe)
4. **[High] Hardcoded colors without dark mode adaptation** — §8.1 — `Color(red:green:blue:)` in 10+ view files
5. **[High] Hardcoded font sizes breaking accessibility** — §8.2 — `.font(.system(size: N))` in 20+ files instead of semantic styles
6. ~~**[High] Force-unwrap of URL(string:) in UI components** — §5.2~~ ✅ Fixed (dynamic URL; hardcoded literals safe)
7. ~~**[High] Static `try!` regex compilation** — §5.3~~ ✅ Fixed (ErrorPattern init; static lets are safe)
8. ~~**[Medium] Port 37001 hardcoded in 10+ locations** — §9.1~~ ✅ Fixed
9. ~~**[Medium] 30+ unguarded `print()` calls in production** — §2.2~~ ✅ Fixed
10. **[Medium] Fire-and-forget Tasks without cancellation** — §3.3 — scattered across ActionDispatcher, TCP client, event monitoring

---

## 2. Quick wins

### 2.1 Remove disabled `#if false` preview providers ✅
- **Location:** `Sources/KeyPathInstallationWizard/UI/Pages/WizardKanataServicePage.swift:583-589`, `WizardInputMonitoringPage.swift:587-593`, `WizardAccessibilityPage.swift:461-467`
- **What:** Three preview providers wrapped in `#if false` — dead code.
- **Why:** Noise; previews should either work or be deleted.
- **Action:** Delete the `#if false`/`#endif` blocks entirely, or convert to modern `#Preview` macro.
- **Severity:** Low

### 2.2 Wrap unguarded `print()` calls in `#if DEBUG` ✅
- **Location:** `Sources/KeyPathAppKit/Models/PhysicalLayout+Builtins.swift` (27 instances), `PhysicalLayoutLoader.swift` (3), `SimulatorKeyboardView.swift` (2), `LauncherKeyboardView.swift` (1), `ActivityLoggingSettingsSection.swift` (1)
- **What:** 30+ `print()` calls in production code without `#if DEBUG` guards.
- **Why:** Console noise in release builds; some print layout loading warnings that could leak filesystem paths.
- **Action:** Wrap in `#if DEBUG` or migrate to `AppLogger.shared.debug()`.
- **Severity:** Medium

### 2.3 Replace `@unchecked Sendable` + NSLock with OSAllocatedUnfairLock ✅ (partial)
- **Location:** `Sources/KeyPathAppKit/Managers/RuntimeCoordinator.swift:67-87` (NotificationTokenStore), `Sources/KeyPathAppKit/Core/HelperManager+RequestHandlers.swift:4-15` (HelperXPCCallCompletionState)
- **What:** Two types use legacy NSLock with `@unchecked Sendable`; the project already uses `OSAllocatedUnfairLock` elsewhere (ServiceHealthChecker).
- **Why:** Inconsistency; OSAllocatedUnfairLock is faster and provides type-safe state access.
- **Action:** Replace NSLock pattern with `OSAllocatedUnfairLock(initialState:)` for consistency.
- **Severity:** Low

### 2.4 Remove stale `@available(*, unavailable)` migration stubs ✅
- **Location:** `Sources/KeyPathAppKit/Managers/KanataDaemonManager.swift:197,210`
- **What:** Methods marked `@available(*, unavailable)` with migration instructions to ServiceLifecycleCoordinator.
- **Why:** Dead code; migration is complete per CLAUDE.md architecture.
- **Action:** Verify no callers remain, then delete the stubs.
- **Severity:** Low

### 2.5 Guard test hooks behind `#if DEBUG` ✅
- **Location:** `Sources/KeyPathAppKit/UI/KeyboardVisualization/KeyboardVisualizationViewModel+TestHooks.swift`
- **What:** Test-only hooks compiled into production binary.
- **Why:** Increases attack surface; adds unnecessary code to release builds.
- **Action:** Wrap in `#if DEBUG` or move to a test-only target.
- **Severity:** Medium

---

## 3. Concurrency

### 3.1 Hanging `withCheckedContinuation` without timeouts ✅
- **Location:** `Sources/KeyPathAppKit/Managers/RuntimeCoordinator.swift:1405-1407` (conflict resolution dialog), `Sources/KeyPathAppKit/Infrastructure/Config/ConfigurationService.swift:593,622,635,648,665` (file operations), `Sources/KeyPathPermissions/PermissionOracle.swift` (permission callbacks)
- **What:** Multiple `withCheckedContinuation` blocks wrap callback-based APIs without timeout protection; if the callback never fires, the continuation hangs indefinitely.
- **Why:** Hanging continuations block the caller's Task permanently. In RuntimeCoordinator, this blocks MainActor if the user ignores the conflict dialog. In ConfigurationService, a failed file operation could hang config reload.
- **Action:** Wrap with a timeout pattern using `Task.sleep()` + cancellation, or use `withTimeoutCancellation`; ensure every callback path resumes the continuation.
- **Severity:** High

### 3.2 `DispatchQueue.main.async` in async contexts
- **Location:** `Sources/KeyPathAppKit/Services/Configuration/ConfigFileWatcher.swift` (DispatchSource callbacks), 60+ files in `Sources/KeyPathAppKit/UI/` (`.asyncAfter` for animation delays)
- **What:** Legacy `DispatchQueue.main.async` and `.asyncAfter` used where structured concurrency equivalents exist.
- **Why:** Bypasses typed MainActor isolation; prevents compiler checking; `.asyncAfter` work items are not cancellable.
- **Action:** Replace prominent instances with `Task { @MainActor in ... }` and `Task { try? await Task.sleep(for:) ... }`.
- **Severity:** Low

### 3.3 Fire-and-forget Tasks without cancellation tracking
- **Location:** `Sources/KeyPathAppKit/Services/ActionDispatcher.swift:241,327` (notification + TCP tasks), `Sources/KeyPathAppKit/Services/RuleCollections/RuleCollectionsManager+EventMonitoring.swift` (background listener), `Sources/KeyPathAppKit/Services/Networking/KanataTCPClient.swift` (multiple)
- **What:** `Task { ... }` and `Task.detached { ... }` spawned without storing references; no way to cancel them.
- **Why:** Tasks continue after their context is torn down; errors in detached tasks (especially TCP) are silently lost.
- **Action:** Store task references (`private var activeTask: Task<Void, Never>?`); cancel in deinit or on new operations. Propagate errors from TCP listener back to coordinator.
- **Severity:** Medium

### 3.4 Actor reentrancy hazard in RuntimeCoordinator warning expiry ✅
- **Location:** `Sources/KeyPathAppKit/Managers/RuntimeCoordinator.swift:410-420`
- **What:** `onWarning` sets `lastWarning` then schedules a `Task.sleep()` to clear it after delay; if a second warning arrives before the first expires, the first Task clears the second warning.
- **Why:** Warning display flickers or disappears prematurely under rapid error conditions.
- **Action:** Store `warningExpiryTask: Task<Void, Never>?`, cancel prior task before creating new one; only clear if warning matches.
- **Severity:** Medium

### 3.5 `nonisolated(unsafe)` dependency container in WizardDependencies
- **Location:** `Sources/KeyPathWizardCore/WizardDependencies.swift:25-104`
- **What:** 10+ `nonisolated(unsafe) public static` properties serve as a dependency container accessed from multiple isolation contexts.
- **Why:** Relies on implicit single-threaded wizard lifecycle without compiler enforcement or documentation.
- **Action:** Document thread-safety assumptions; consider actor-based DI if wizard becomes concurrent.
- **Severity:** Low

### 3.6 HIDDeviceMonitor MainActor class with nonisolated IOKit thread
- **Location:** `Sources/KeyPathAppKit/Services/Devices/HIDDeviceMonitor.swift:11-203`
- **What:** `@MainActor final class HIDDeviceMonitor: ObservableObject` uses `nonisolated(unsafe)` for `monitorThread`, `_monitorRunLoop`, `hidManager` to support IOKit callbacks on a dedicated CFRunLoop thread.
- **Why:** Thread boundary between MainActor and IOKit CFRunLoop is implicit; IOKit callbacks mutate state that must cross to MainActor for UI updates.
- **Action:** Redesign as a nonisolated coordinator that sends Sendable snapshots to MainActor, or add explicit SAFETY comments documenting the boundary.
- **Severity:** Medium

---

## 4. API modernity

### 4.1 Lingering `ObservableObject` / `@Published` types
- **Location:** `Sources/KeyPathAppKit/Services/Devices/HIDDeviceMonitor.swift:11` (ObservableObject + @Published), `DragToAuthorizeController`, `LayoutTracerMenuState`
- **What:** Three types still use pre-Swift 5.9 `ObservableObject` pattern; the rest of the codebase uses `@Observable`.
- **Why:** Inconsistency; `@Observable` provides more efficient reactive updates and simpler SwiftUI integration.
- **Action:** Migrate to `@Observable` macro; update SwiftUI views to use `@Bindable` instead of `@ObservedObject`.
- **Severity:** Low

### 4.2 XPC callback protocol constrained by Objective-C bridge
- **Location:** `Sources/KeyPathHelper/HelperService.swift` (32 `reply: @escaping (Bool, String?) -> Void` callbacks)
- **What:** All HelperService methods use callback-based XPC protocol; no async overloads.
- **Why:** XPC/NSXPCInterface requires Objective-C-compatible protocol; async/await cannot replace the protocol definition. The wrapping layer (HelperManager) correctly bridges to async/await.
- **Action:** No action needed — this is a platform constraint. Document that HelperManager is the async boundary.
- **Severity:** Low

---

## 5. Bugs / logic errors

### 5.1 Shell command injection via NSUserName() in AppleScript ✅
- **Location:** `Sources/KeyPathAppKit/Managers/InstallationCoordinator.swift:132`
- **What:** `NSUserName()` is interpolated directly into an AppleScript `do shell script` without escaping: `"chown -R \(NSUserName()) '\(tmpPath)'"`.
- **Why:** If the macOS username contains shell metacharacters (e.g., `user'; rm -rf /; '`), the injected command runs with administrator privileges via the `with administrator privileges` clause. While macOS usernames rarely contain special characters, this violates defense-in-depth for a privileged operation.
- **Action:** Shell-escape the username with single-quote wrapping and internal quote escaping, or use `ProcessInfo.processInfo.userName` with proper quoting. Apply the same fix to `karabinerLogDir` on line 158.
- **Severity:** Critical

### 5.2 Force-unwrap of URL(string:) in UI components ✅
- **Location:** `Sources/KeyPathAppKit/UI/Settings/SettingsView+AIConfig.swift:138,304`, `HelpBrowserView.swift:200,204`, `VirtualKeysInspectorView.swift:110`, `CommandPaletteView.swift:25`
- **What:** `URL(string: "https://...")!` force-unwraps hardcoded URL strings; a typo in any of these crashes the app.
- **Why:** Runtime crash on malformed URL string; no recovery path.
- **Action:** Use `URL(string:)` with nil-coalescing or guard-let; define URLs as validated static constants.
- **Severity:** High

### 5.3 Static `try!` regex compilation ✅ (ErrorPattern init)
- **Location:** `Sources/KeyPathAppKit/UI/KeyboardVisualization/KeyboardVisualizationViewModel+LayoutMapping.swift:451,458,465,472`, `Sources/KeyPathAppKit/Services/Karabiner/KarabinerConverterService.swift:62,64,66`, `Sources/KeyPathAppKit/Services/Monitoring/KanataErrorMonitor.swift:108`
- **What:** 8 `try! NSRegularExpression(pattern:)` calls crash the app at static init time if a pattern is malformed.
- **Why:** While patterns are hardcoded and tested, any developer typo during a refactor crashes the app on launch with no error handling.
- **Action:** Add unit tests that validate all regex patterns compile successfully; consider wrapping in a factory that returns Optional with logging.
- **Severity:** High

### 5.4 Force-cast `as!` in Accessibility API code ✅ (verified safe — CF bridging)
- **Location:** `Sources/KeyPathAppKit/Services/System/WindowManager.swift:466,493,506`
- **What:** Three `as!` casts on CoreFoundation accessibility API return values; comments say "CF bridging always succeeds" but this depends on undocumented runtime behavior.
- **Why:** If macOS changes AX API return types, these crash at runtime with no recovery.
- **Action:** Use `as?` with guard-let; document which AX functions guarantee type safety.
- **Severity:** High

### 5.5 Dictionary force-unwrap in CommandPaletteView ✅
- **Location:** `Sources/KeyPathAppKit/UI/CommandPalette/CommandPaletteView.swift:25`
- **What:** `groups[$0]!` force-unwraps a dictionary lookup; while the key set appears to match, any future refactor that breaks the invariant crashes the view.
- **Why:** Runtime crash if key doesn't exist in dictionary.
- **Action:** Use `groups[$0] ?? []` or guard-let.
- **Severity:** High

### 5.6 Error-eating `catch {}` blocks
- **Location:** `Sources/KeyPathHelper/HelperService.swift:411,649`, `Sources/KeyPathDaemonLifecycle/ProcessLifecycleManager.swift:107,120,268` (and 10+ others)
- **What:** Multiple catch blocks that log the error but continue as if the operation succeeded.
- **Why:** Silent failures mask real problems; a failed chmod in uninstall leaves dangling permissions.
- **Action:** For each catch block, decide: propagate, convert to Result, or document why silent failure is safe.
- **Severity:** Medium

### 5.7 onAppear Task race in RulesSummaryView
- **Location:** `Sources/KeyPathAppKit/UI/Rules/RulesSummaryView.swift:694-708`
- **What:** `.onAppear` mutates multiple @State properties and spawns a Task with no cancellation on `.onDisappear`.
- **Why:** If the view is removed and re-added quickly, the Task from the first appearance may conflict with the second.
- **Action:** Store Task reference in @State; cancel in .onDisappear; check Task.isCancelled before updating state.
- **Severity:** Medium

---

## 6. Security

### 6.1 Path traversal in VHID driver installation ✅
- **Location:** `Sources/KeyPathHelper/HelperService.swift:239`
- **What:** Path validation uses `pkgPath.contains("/KeyPath.app/")` and `hasSuffix(".pkg")` but doesn't canonicalize the path; `/../` sequences bypass the containment check.
- **Why:** A crafted path like `/Applications/KeyPath.app/../../tmp/malicious.pkg` passes both checks but installs an arbitrary package as root. Mitigated by XPC code signature validation (only KeyPath.app can call this method), but defense-in-depth requires canonicalization.
- **Action:** Canonicalize with `URL(fileURLWithPath: pkgPath).standardized.path` or `realpath()` before validation; reject paths that don't start with the resolved KeyPath.app bundle path.
- **Severity:** Critical

### 6.2 XPC code signature validation is present and sound
- **Location:** `Sources/KeyPathHelper/main.swift:23-93, 103-140`
- **What:** The helper validates all XPC connections using `SecCodeCopyGuestWithAttributes` + `SecCodeCheckValidity` against a code signing requirement. Release builds require exact bundle identifier + team ID.
- **Why:** This is correctly implemented. Agent C initially flagged this as missing, but verification confirmed it's sound.
- **Action:** No action needed — well-implemented. Consider adding audit-token-based validation as an additional layer for future hardening.
- **Severity:** _Verified — no issue_

### 6.3 TCP port not validated on read from preferences ✅ (already implemented — isValidPort validates on init)
- **Location:** `Sources/KeyPathAppKit/Services/Configuration/PreferencesService.swift` (tcpServerPort)
- **What:** TCP port number read from user preferences without range validation.
- **Why:** Invalid port (0, >65535, or privileged <1024) could cause bind failures or security issues.
- **Action:** Validate port range on read; clamp to 49152-65535 (dynamic/private range) or documented valid range.
- **Severity:** Medium

### 6.4 Historical `executeCommand` removal documented
- **Location:** `Sources/KeyPathHelper/HelperProtocol.swift:89`, `Sources/KeyPathAppKit/Core/HelperProtocol.swift:89`
- **What:** Comment "executeCommand removed for security reasons" — good security decision, but lacks context for future maintainers.
- **Why:** Without explanation, a future developer might re-introduce generic command execution.
- **Action:** Add a brief security note explaining the command injection risk that motivated removal.
- **Severity:** Low

---

## 7. Performance

### 7.1 Config file re-parsed on every reload without content-change check
- **Location:** `Sources/KeyPathAppKit/Infrastructure/Config/ConfigurationService.swift:68-109`
- **What:** Every config reload re-parses the entire Kanata config file (chord groups, sequences, validation) even if file content hasn't changed.
- **Why:** On large configs (1000+ mappings), repeated reloads from preference changes or device selection re-parse identical data.
- **Action:** Add content hash or last-modified timestamp check; skip parse if unchanged.
- **Severity:** Medium

### 7.2 DateFormatter created in computed property ✅
- **Location:** `Sources/KeyPathAppKit/UI/Gallery/KindaVimInsightsView.swift:192-203`
- **What:** `chartSeries` computed property creates a new DateFormatter per iteration; recalculated on every view redraw.
- **Why:** DateFormatter is expensive to create; causing potential jank in chart rendering.
- **Action:** Move to a `private static let` formatter.
- **Severity:** Medium

### 7.3 Large computed property chains in RulesSummaryView
- **Location:** `Sources/KeyPathAppKit/UI/Rules/RulesSummaryView.swift:65-154`
- **What:** Five computed properties (allCollections -> sortedCollections -> filteredCollections -> filteredCustomRules -> filteredAppKeymaps) chain filtering and sorting on every render.
- **Why:** Scales poorly with large rule sets; each render recalculates the full chain.
- **Action:** Cache results in @State; recalculate only via `.onChange` of dependencies.
- **Severity:** Medium

### 7.4 JSONDecoder created inline in view code
- **Location:** `Sources/KeyPathAppKit/UI/Overlay/QMKKeyboardSearchView.swift`, `KeyboardSelectionGridView.swift`
- **What:** `try JSONDecoder().decode(...)` called inline without caching the decoder instance.
- **Why:** Decoder allocation on every call; unnecessary overhead in hot UI paths.
- **Action:** Use a static cached decoder.
- **Severity:** Low

### 7.5 FloatingKeymapLabel missing Equatable in ForEach
- **Location:** `Sources/KeyPathAppKit/UI/Overlay/OverlayKeyboardView.swift:282`
- **What:** FloatingKeymapLabel rendered in ForEach without Equatable conformance; receives 7+ parameters.
- **Why:** SwiftUI cannot diff-optimize; all labels re-render on any parent state change.
- **Action:** Add Equatable conformance comparing only relevant display parameters.
- **Severity:** Medium

---

## 8. SwiftUI / UI

### 8.1 Hardcoded colors without dark mode adaptation
- **Location:** `Sources/KeyPathAppKit/UI/SplashView.swift` (Color(red:green:blue:)), `ContextHUD/ContextHUDViewModel.swift`, `KeyboardTransforms/KeycapStyle.swift`, 7+ other files
- **What:** RGB colors via `Color(red:green:blue:)` and hex values that don't adapt to system appearance.
- **Why:** Poor contrast or unreadable text in dark mode; bypasses SwiftUI's semantic color system.
- **Action:** Use semantic colors (`.primary`, `.secondary`) or named asset catalog colors that adapt; wrap custom colors in a Theme utility that switches on `colorScheme`.
- **Severity:** High

### 8.2 Hardcoded font sizes instead of semantic text styles
- **Location:** `ContextHUD/ContextHUDKindaVimLearningView.swift`, `VimKeyBadge.swift`, `TransformKeycap.swift`, 20+ files
- **What:** `.font(.system(size: 11))`, `.font(.system(size: 14))`, etc. instead of `.font(.body)`, `.font(.caption)`.
- **Why:** Hardcoded sizes don't scale with Dynamic Type accessibility settings; users with larger text preferences see unchanged sizes.
- **Action:** Use semantic styles (`.body`, `.caption`, `.subheadline`); for custom sizing use `@ScaledMetric`.
- **Severity:** High

### 8.3 Excessive @State declarations in RulesSummaryView
- **Location:** `Sources/KeyPathAppKit/UI/Rules/RulesSummaryView.swift:9-43`
- **What:** 21 separate `@State` declarations including dictionaries, optionals, and sets.
- **Why:** Maintenance burden; harder to reason about state coherence with 21 independent state variables.
- **Action:** Consolidate into a `struct RulesSummaryState` with all mutable fields; access via single `@State`.
- **Severity:** Low

### 8.4 Large modifier chains in OverlayMapperSection
- **Location:** `Sources/KeyPathAppKit/UI/Overlay/OverlayMapperSection.swift:62-120`
- **What:** Body view chains 16+ `.onChange()` modifiers using intermediate `let` bindings, spanning 750+ lines.
- **Why:** Obscures core view hierarchy; makes testing individual interactions difficult.
- **Action:** Extract modifier chains into named ViewModifier types or extension methods.
- **Severity:** Medium

### 8.5 Inline `@Bindable` declaration in view body
- **Location:** `Sources/KeyPathAppKit/UI/Rules/RulesSummaryView.swift:482-483`
- **What:** `@Bindable var kanataManager = kanataManager` declared inside body; recreated on every render.
- **Why:** Potential for unnecessary view identity changes on redraws.
- **Action:** Move `@Bindable` to a view-level property outside body.
- **Severity:** Low

### 8.6 Hardcoded keyboard layout dimensions
- **Location:** `Sources/KeyPathAppKit/UI/Overlay/OverlayKeyboardView.swift:106`
- **What:** `keyUnitSize: CGFloat = 32` and `keyGap: CGFloat = 2` hardcoded; layout doesn't adapt to screen size or accessibility settings.
- **Why:** On different displays or with accessibility zoom, keyboard overlay may be too small or overflow.
- **Action:** Use GeometryReader with calculated scales; consider accessibility-aware sizing.
- **Severity:** Medium

### 8.7 Missing accessibility labels on icon-only controls
- **Location:** Various view files (pattern gap, not comprehensively catalogued)
- **What:** Icon-only buttons and controls without `.accessibilityLabel()` modifiers.
- **Why:** VoiceOver users cannot identify the purpose of unlabeled controls.
- **Action:** Audit all icon-only buttons and add descriptive accessibility labels.
- **Severity:** Medium

---

## 9. Dead code / duplication / refactor

### 9.1 Port 37001 hardcoded in 10+ locations ✅
- **Location:** `Sources/KeyPathAppKit/UI/SimpleModsView.swift:260`, `Core/ServiceInstallGuard.swift:93`, `Services/Configuration/PreferencesService.swift:390`, `KeyPathInstallationWizard/Core/ServiceHealthChecker.swift:442,474,504`, `KeyPathInstallationWizard/Core/PlistGenerator.swift:45,73`, and others
- **What:** TCP port 37001 appears as a magic number in 10+ files without a single named constant.
- **Why:** Port changes require find-and-replace across the entire codebase; easy to miss a site.
- **Action:** Define `KanataNetworking.defaultPort` (or similar) as a single constant; reference everywhere.
- **Severity:** Medium

### 9.2 Notification.Name definitions scattered across 6 locations
- **Location:** `Sources/KeyPathWizardCore/WizardServiceProtocols.swift:97-100`, `Sources/KeyPathAppKit/Utilities/Notifications.swift:5-60`, `UI/Mapper/MapperView.swift:9`, `UI/Overlay/LiveKeyboardOverlayTypes.swift:183-211`, `UI/Preferences/WindowHeightPreferenceKey.swift:14`, `KeyPathInsights/InsightsPreferences.swift:46`
- **What:** Notification names defined in 6 separate extension blocks across different modules.
- **Why:** No centralized notification registry; discovery and deduplication require searching the entire codebase.
- **Action:** Consolidate all notification definitions into `Notifications.swift` with organized sections per module.
- **Severity:** Medium

### 9.3 Timing constants scattered without centralization
- **Location:** `KeyboardVisualizationViewModel.swift` (tcpConnectionTimeout=3.0, idleTimeout=10), `MainAppStateController.swift` (validationCooldown=30.0, startupGracePeriod=3.0), `PreferencesService.swift` (contextHUDTimeout=3.0), `KanataErrorMonitor.swift` (patternCountWindow=60.0, toastCooldown=300.0)
- **What:** Magic timing values (3.0s, 5.0s, 10.0s, 30.0s, 60.0s, 300.0s) scattered across 20+ files.
- **Why:** Behavior tuning requires finding and updating multiple files; values are hard to audit.
- **Action:** Create a centralized `Timeouts` or `TimingConstants` namespace for service-level timeouts.
- **Severity:** Low

### 9.4 Duplicate config path construction
- **Location:** `Sources/KeyPathAppKit/Services/Packs/PackInstaller.swift:545`, `InstalledPackTracker.swift:50`
- **What:** Both files construct identical path to keypath directory using `.appendingPathComponent("keypath", isDirectory: true)`.
- **Why:** Directory structure changes require updating multiple files.
- **Action:** Create shared `ConfigPaths.keyPathPacksDirectory` constant.
- **Severity:** Low

### 9.5 TODO/FIXME markers pending resolution
- **Location:** `QMKKeycodeMapping.swift:299` (HID descriptor integration), `PackInstaller.swift:93` (multi-system pack support), `KindaVimTelemetryStore.swift:169` (correctness coverage), `PreviewFixtures.swift:56` (multi-device upstream), `DeviceEnumerationService.swift:57` (upstream issue #254)
- **What:** 5 TODO markers indicating deferred work.
- **Why:** Technical debt tracking; most are blocked on upstream dependencies.
- **Action:** Verify each is tracked in project management; remove or update stale TODOs.
- **Severity:** Low

### 9.6 Inline JSONEncoder/JSONDecoder without shared instances
- **Location:** `KanataTCPClient+Parsing.swift:137`, `KanataTCPClient+Operations.swift` (11+ instances), `QMKLayoutParser.swift` (3), `SimulatorService.swift` (2)
- **What:** 30+ inline `JSONEncoder()` / `JSONDecoder()` instantiations across the codebase.
- **Why:** No centralized serialization layer; harder to add custom encoding strategies consistently.
- **Action:** Create shared static instances; most JSON operations don't need custom strategies.
- **Severity:** Low

### 9.7 Large files that could benefit from splitting
- **Location:** `RuntimeCoordinator.swift` (1487), `WizardDesignSystem.swift` (1242), `LauncherCollectionView.swift` (1053), `RuleCollectionCatalog.swift` (1039), `RulesSummaryView.swift` (1034), `ServiceBootstrapper.swift` (1029), `ConfigurationService.swift` (1001), `KarabinerConverterService.swift` (995)
- **What:** 8 files exceed 1000 lines; several already use MARK sections or extensions indicating natural split points.
- **Why:** Large files are harder to navigate and review; RuntimeCoordinator at 1487 lines is the largest.
- **Action:** Split along existing extension/MARK boundaries (e.g., RuntimeCoordinator+Lifecycle, +Configuration, +Health). Not urgent — architecture is sound.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

### 10.1 Establish a continuation timeout pattern
Every `withCheckedContinuation` in the codebase should be wrapped in a standard timeout utility. Define a single `withTimeoutContinuation(seconds:)` helper that handles the timeout/cancellation pattern, then apply it to all 20 continuation sites. This eliminates the hanging-continuation class of bugs entirely.

### 10.2 Centralize magic constants
Port numbers, timing values, and directory paths should each have a single source of truth. The existing `KeyPathConstants` namespace is a good home; extend it with `Networking.defaultPort`, `Timeouts.*`, and `Paths.*` sections.

### 10.3 Audit accessibility systematically
The hardcoded fonts and colors findings suggest accessibility hasn't been audited holistically. A one-pass audit of all views for VoiceOver labels, Dynamic Type support, and dark mode adaptation would improve the app's accessibility posture significantly.

### 10.4 Standardize Task lifecycle management
Adopt a consistent pattern for background Tasks: store references, cancel in deinit/onDisappear, and propagate errors. Consider a lightweight `TaskBag` or similar utility to manage multiple concurrent tasks per coordinator.

---

## 11. What was NOT audited

- **Kanata configuration generation correctness** — the kanata `.kbd` output was not validated against the kanata parser; only code-level patterns were reviewed.
- **Metal / GPU code** — no Metal shaders or GPU pipelines exist in this project.
- **Test coverage assessment** — tests exist (283 files, ~56K LOC, ~532 tests) but test completeness and quality were not evaluated.
- **Build settings and Xcode project structure** — the project uses SwiftPM (Package.swift); no Xcode project was evaluated.
- **Third-party dependency internals** — SPM dependencies (swift-syntax, swift-argument-parser, etc.) were treated as black boxes.
- **Localization correctness** — string translations were not audited.
- **Performance profiling** — no Instruments traces were run; findings are based on code pattern analysis only.
- **Network security / TLS** — TCP communication between app and Kanata was not assessed for transport-layer security (it's localhost-only by design).
- **Entitlements and sandbox configuration** — not reviewed in this pass.

---

## 12. Verification

For each Critical and High finding, the cited lines were opened and verified:

- **§5.1** — Opened `Sources/KeyPathAppKit/Managers/InstallationCoordinator.swift:130-135`. Confirmed: `NSUserName()` is interpolated directly into `do shell script` with `with administrator privileges`. No escaping function is called. The `rootOnlyPath` and `tmpPath` come from `KeyPathConstants` (safe), but `NSUserName()` comes from the system and is not sanitized.

- **§6.1** — Opened `Sources/KeyPathHelper/HelperService.swift:235-244`. Confirmed: path validation is `pkgPath.contains("/KeyPath.app/")` which matches anywhere in the string and does not canonicalize. A path like `/Applications/KeyPath.app/../../tmp/evil.pkg` passes both checks. Mitigated by XPC code signature validation (only KeyPath.app can call this method), but defense-in-depth requires canonicalization.

- **§6.2** — Opened `Sources/KeyPathHelper/main.swift:23-140`. Confirmed: XPC validation **is present and correct** — uses `SecCodeCopyGuestWithAttributes` + `SecCodeCheckValidity` with team ID + bundle identifier requirement in release builds. Agent C's initial claim of missing validation was **incorrect**; verified as no issue.

- **§3.1** — Opened `Sources/KeyPathAppKit/Managers/RuntimeCoordinator.swift:1405-1407`. Confirmed: `withCheckedContinuation { continuation in self.conflictResolutionContinuation = continuation }` stores the continuation in a property with no timeout. If `resolveConflict()` is never called, the continuation hangs permanently.

- **§5.2** — Grep confirmed 6+ instances of `URL(string: "...")!` across UI files. All are hardcoded HTTPS URLs; risk is developer typo causing launch crash.

- **§5.3** — Grep confirmed 8 instances of `try! NSRegularExpression(pattern:)` across 3 files. All are static let initializers that run at first access; a malformed pattern crashes the app.

- **§5.4** — Opened `Sources/KeyPathAppKit/Services/System/WindowManager.swift:466,493,506`. Confirmed: `as!` casts on AXUIElement return values. Comments explain the assumption; the cast could fail if macOS changes AX API behavior.

- **§8.1** — Grep confirmed `Color(red:` pattern in SplashView.swift and 7+ other files. These are fixed RGB values without colorScheme adaptation.

- **§8.2** — Grep confirmed `.system(size:` pattern in 20+ files with hardcoded point sizes (11, 13, 14, 15, 18, 20).
