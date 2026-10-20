# Architectural review: rule admission, backend capability and conflicts

**Status:** Proposal for review (2026-10-19). No product code changes.
**Builds on:** [ADR-039 Key Conflict Detection and Resolution Principles](../adr/adr-039-key-conflict-resolution-principles.md).
**Prompted by:** the media-key and Caps Lock work on the driverless runtime
(#1303–#1309), where three faults in one day shared a cause: a rule that the
backend cannot run is discovered only when the whole configuration is rejected.

## 1. The question

Three things look separate and are not:

1. **Backend capability.** The driverless session runtime cannot send consumer
   keys (brightness, media), cannot filter by device, and needs Caps Lock to be
   remapped to a spare key at the HID layer. A driver backend could do all of
   these. Micah may switch backends later.
2. **Catalog capability.** The rule catalog never declares what a collection
   needs. Whether a collection can run is recoverable only from the keys it
   emits, so every check reverse-engineers it.
3. **Conflicts.** Two rules claiming one key, a rule claiming the key reserved
   for Caps Lock, a rule emitting a key the backend lacks, another app holding
   Caps Lock, a pack that is mutually exclusive with another: all are "this rule
   cannot be admitted as written", but each is detected by its own code, at its
   own moment, with its own message.

The proposal is one **admission** layer: every rule, collection, pack and
reserved key produces *claims* and *requirements*; one engine checks them
against each other and against the active backend's *capability profile*; every
caller (editor, toggle, pack preview, catalog update, save, startup, CLI
`doctor`) gets the same verdicts, attributed to the rule that caused them.

## 2. Inventory

File:line references are against `design/driverless-caps-ui` at `8f8e0499b`.
The stacked branches add `keypath doctor` (#1306) and a free-key choice from
F13–F20 (#1307, #1309); noted where relevant.

### 2.1 Where backend capability is decided today

| Site | What it encodes |
|---|---|
| `Rust/KeyPathKanataHostBridge/src/session_config.rs:7-10` `key_supported` | an output key must be HID page 7 **and** in the usage list the host passed. This is what rejects consumer keys and Fn. |
| `session_config.rs:12-28` `custom_supported` | allow-list of custom actions (PushMessage, FakeKey*, Delay*, …). |
| `session_config.rs:30-113` `action_supported` | the action tree walk; managed mode also rejects `Trans`/`Src`/`Repeat` and F18 output. |
| `session_config.rs:115-175` `supported`, `:179-259` `supported_with_managed_caps` | up-front rejects: device filters, overrides, zippy, start_alias; managed adds "Caps in defsrc, F18 not in defsrc". The two functions repeat the same structure. |
| `lib.rs:44, :94, :96` | the three rejection strings. The "advanced driver backend" text appears twice. |
| `Sources/KeyPathCore/SessionRuntime/SessionKeyMap.swift:9-31` | the Swift list of representable keys; Fn, volume keys and `menu` are absent. The usage list passed to Rust is derived from it. |
| `SessionCapsRuntimeSupport.swift:49-71` `validate` | legacy profile first, then managed; the user sees the *legacy* reason when both fail. |
| `ConfigurationService+Validation.swift:9-29` | wraps the Rust reason: "This configuration cannot run in the driverless session: … Existing rules were preserved." |
| `ConfigReloadCoordinator.swift:401-407` | a second wrapper with a different generic message. |
| `MainAppStateController.swift:789` | a third: WizardIssue "Configuration cannot run in driverless mode". |
| `ConfigurationService.swift:1735-1757` `validKanataPassthrough` | the generator passes media keys, `fn`, `menu`, `comp` through freely; no session awareness. |
| `SystemActionInfo.swift:43-51` | a deny-list spelled `voldwn`/`brdown`. |
| `RuleCollectionCatalog.swift:173-206` `functionKeyMappings(.media)` | emits `vold`/`brdn`. **The two Swift lists spell the same keys differently.** |
| `RuleCollectionModels.swift:313-318` `FunctionKeyMode.isSupportedInDriverlessSession` | mode-level flag for one collection only. |
| `RuleCollectionCatalog.swift:6-8` `driverlessUnavailableReason(for:)` | hard-codes the Fun layer as unavailable; the only per-collection check. Called from five UI/installer sites. |
| `KanataConfigurationGenerator.swift:308-350` | still emits `macos-dev-names-*` when devices are known, which Rust rejects outright. |
| `DeviceSelectionView.swift:4,62` | UI copy saying device targeting is unsupported. |
| `KanataRuntimeBackend.swift:3-16` | `enum { driverKit, session }`; used for lifecycle and permissions in 14 places, never for feature capability. |

Consumer keys are encoded four times (SessionKeyMap omission + Rust page-7
check; `SystemActionInfo` deny-list; `FunctionKeyMode` flag + media mappings;
`driverlessUnavailableReason`). F18 = 109 is spelled independently in four
places. "Rules use Caps" is detected three ways.

### 2.2 Where conflicts are detected today

| Moment | Code | Compares | Type |
|---|---|---|---|
| Toggle / add / rule save | `RuleCollectionsManager+ConflictDetection.swift:27` `conflictInfo` | candidate vs enabled collections on the same layer; activator vs mapping; activator vs activator; custom rules on the same layer. Returns **only the first** hit. Ignores leader key, chord groups, aliases, app keymaps. | `RuleConflictInfo` (UUID identity) |
| Generation (authoritative) | `RuleCollectionDeduplicator.swift:14` `detectConflicts` | the whole config: collections, custom rules, leader slot, activators, chord groups, alias names. Throws `.mappingConflicts`. | `MappingConflictInfo` (**name** identity, not unique) |
| After detection | `RuleCollectionDeduplicator.dedupe:262`, `deduplicateAliases/Blocks` (`KanataConfiguration+BlockBuilders.swift:527`) | silent safety nets; `dedupe` keys activators by *target* layer while detection keys them by *source* layer, so what detection misses is dropped silently (ADR-039 principle 1 violation, still open). | — |
| Dependencies | `RuleCollectionDependencyExtractor.swift:11` → `RuleDependencyGraph.swift` | `layerContent`, `layerActivation`, `keyAlias(.hyper)` only; inferred from configuration and hard-coded ids. | `RulePrerequisite`, `RuleDependentMapping` |
| Packs | `PackDependencyChecker.swift` | `requires`/`enhancedBy` only. **`conflictsWith` is declared (`PackRegistry.swift:105,110`) and never read.** `enforcePreInstallGates:629` hard-codes KindaVim vs Vim. Install then auto-resolves key conflicts without asking (`PackInstaller.swift:240`). | `PackDependency` |
| Engine | Rust `session_config` + `SessionCapsMappingPolicy.swift:187-196` | backend limits; Caps already mapped by another app; F18 collision. Surfaced only as the worker failure string `managed-caps-activation-refused: …`. | strings |
| App keymaps | `AppConfigGenerator.swift:139` | duplicates **within one app** only; never against global rules. | — |
| Sequences | `SequencesConfig.detectConflicts` | editor only; not in `detectConflicts`. | — |

Five resolution dialogs exist: `RuleConflictResolutionDialog` (toggle-time),
`MappingConflictResolutionDialog` (save-time), `PackConflictResolutionDialog`,
`MapperConflictDialog` (hold vs tap-dance inside one key), and
`ConflictResolutionDialog`, which nothing instantiates. A single action can
prompt the first and then the second for the same key.

### 2.3 What the catalog declares

`rule-collection-catalog.json` holds 22 collections and declares **no
requirements**. The catalog copy of macOS Function Keys is the *media*
definition with no `functionKeyMode`; the fresh-profile default rewrites it to
plain F1–F12 (`RuleCollectionCatalog.swift:15-18`), and a lost entry is refilled
the same way (`RuleCollectionStore.swift:196-212`), so catalog changes to that
collection can never be offered as updates. Window Snapping needs Accessibility
only as prose in a pack description. Caps Lock Remap needs Caps only through
`input: "caps"`. Device targeting is never expressed. `Pack` has
`dependencies` and `ConfigPredicate` but no capability field.

## 3. Findings

1. **No rule-level admission against the backend.** A rule using `volu`,
   `f18` (the reserved key) or `caps` passes `CustomRuleValidator`
   (`CustomRuleValidator.swift:40,148` lists `f18` among *common* keys) and
   every conflict check, then the whole configuration is refused with no
   pointer to the rule. Today's 17 CI failures were this, triggered by a
   catalog refill.
2. **The capability list has no owner.** It is derived in Rust from a usage
   list Swift builds from `SessionKeyMap`, and separately restated in three
   Swift deny-lists and five UI sites. Two of them disagree on spelling. A
   backend switch would need every one found and changed.
3. **Conflict detection is two implementations with two identities.**
   Toggle-time (UUID, first hit only) and generation-time (name, full) diverge;
   `dedupe` diverges from both. ADR-039's "never silently discard" is still
   violated at `deduplicateBlocks`.
4. **Reserved keys are not claims.** The Caps intermediate key (F18 today;
   chosen from F13–F20 on #1307/#1309) and another app's hidutil mappings are
   checked only by the HID lease at session start. Nothing stops a user mapping
   F18, and nothing explains `f18Collision` in the UI.
5. **Requirements are inferred, not declared.** The dependency extractor,
   `driverlessUnavailableReason`, the pack `requires` graph and the prose in
   pack descriptions are four partial reconstructions of "what does this need".
6. **Errors lose attribution at every hop.** Rust → `startupFailureMessage` /
   `requireSessionEligibleConfiguration` / `ConfigReloadCoordinator` /
   `publishSessionConfigurationRefusal` each re-wrap one string. The user can
   see the Rust text nested in two Swift wrappers, and never the rule name.
7. **Layer fall-through is undetected.** Managed Caps rejects `Trans`; the
   generator writes base actions instead; nothing reports which keys stopped
   falling through.

## 4. Proposed design: one admission layer

```
             ┌──────────────────────────┐
  catalog ──▶│ Requirements (declared)  │
  packs   ──▶│ Claims (derived)         │──┐
  rules   ──▶│                          │  │    ┌──────────────────────────┐
             └──────────────────────────┘  ├───▶│   AdmissionEngine        │──▶ [Verdict]
             ┌──────────────────────────┐  │    │ conflicts + capability   │    attributed to
  backend ──▶│ BackendCapabilityProfile │──┘    │ + dependencies           │    rule / collection /
  (bridge)   └──────────────────────────┘       └──────────────────────────┘    pack / reserved key
                                                           │
   editor · toggle · pack preview · catalog update · save · startup · CLI doctor
                                                           │
                                                ┌──────────▼───────────┐
                                                │ Lowering (generator) │ intent → backend output
                                                └──────────────────────┘
                                                           │
                                                ┌──────────▼───────────┐
                                                │ Bridge validation    │ backstop; errors mapped
                                                └──────────────────────┘ back to rule ids
```

### 4.1 `BackendCapabilityProfile` — exported by the bridge

One value, produced by the Rust bridge (a new `keypath_kanata_bridge_capability_profile`
FFI returning JSON), decoded once in Swift, cached per `KanataRuntimeBackend`.

```swift
public struct BackendCapabilityProfile: Codable, Sendable {
    public let backend: KanataRuntimeBackend          // .session | .driverKit
    public let outputUsages: Set<HIDUsage>            // page 7 keys it can post
    public let inputUsages: Set<HIDUsage>             // keys it can capture
    public let consumerOutput: Support                // .native | .viaAdapter | .none
    public let deviceTargeting: Support
    public let capsLock: CapsSupport                  // .native | .managedViaIntermediate(candidates: [HIDUsage])
    public let layerTransparency: Support             // can a non-base layer fall through?
    public let customActions: Set<CustomActionKind>   // push-msg, fake-key, delay…
    public let reservedInputs: [ReservedKey]          // filled at runtime: Caps intermediate, foreign hidutil mappings
}
```

Rust keeps the final say (`session_config::supported` becomes "does this
config stay inside the profile I exported"), so Swift and Rust cannot drift.
`SessionKeyMap` becomes the Swift *decoder* of `outputUsages`, not a second
source. The three Swift deny-lists and `driverlessUnavailableReason` are
deleted. A driver backend ships a profile with `consumerOutput: .native`,
`deviceTargeting: .native`, `capsLock: .native`; nothing else changes.

### 4.1a What phase 1 actually built (2026-10-19)

The design above describes a full profile object exported as JSON. Reading the
code showed the duplication was narrower than that: the Rust session check
already takes its allowed output keys from Swift's `SessionKeyMap`, so the key
list itself was never copied. What was copied was the *rule* (keyboard page only;
media and brightness refused) in three hand-written Swift deny-lists and a
hard-coded collection id. Phase 1 therefore exports the rule, not a list:

- **Rust:** `session_config::output_key_name_supported(name, usages)` applies the
  same `oscode_supported` + `session_output_usages` helpers `supported` uses, so
  the query and validation cannot disagree. FFI:
  `keypath_kanata_bridge_session_output_key_supported` (1 / 0 / -1 unknown).
- **Swift:** `BackendCapabilityProfile` (KeyPathCore) answers `canEmit(kanataKey:)`
  per base key (modifier prefixes stripped), cached, and `supportsDeviceTargeting`.
  Only the session backend has limits. With no bridge answer it keeps the previous
  behaviour (refuse only consumer keys); session validation stays the backstop.
- **Callers:** `SystemActionInfo.isSupportedInDriverlessSession`,
  `FunctionKeyMode.isSupportedInDriverlessSession` (now derived from the mode's
  mappings) and `RuleCollectionCatalog.driverlessUnavailableReason` (derived from
  the collection *as installed*: macOS Function Keys is stored as its media
  definition but installed in function mode). Public names unchanged.
- **Not done here:** `validKanataPassthrough` still checks name validity only; the
  generator's lowering stage (phase 6) is where backend output belongs.
  Fields of §4.1 with no consumer yet (`inputUsages`, `layerTransparency`,
  `customActions`) are deliberately not exported until a phase needs them.

### 4.2 Requirements: inferred where derivable, declared only otherwise

Extend `RuleCapability` (`RuleDependencyGraph.swift:37`) from three cases to a
closed set:

```swift
public enum RuleCapability: Codable, Hashable {
    case layerContent(layer), layerActivation(layer), keyAlias(.hyper)   // existing
    case consumerOutput              // media / brightness keys
    case capsLockInput               // remaps Caps Lock
    case deviceTargeting
    case accessibilityPermission     // push-msg window:* / system:*
    case reservedKey(HIDUsage)       // e.g. a mapping on F18
    case externalApp(bundleID)       // e.g. kindaVim.app present
}
```

Every case above except `externalApp` is mechanically derivable from a
collection's mappings and actions, exactly as the extractor already derives
layers and Hyper. So the extractor infers them, and the catalog gets **one
optional `requires` field for needs that cannot be read from the rules**
(an external app; a permission the actions do not imply). The two sets are
merged. There is deliberately no hand-written copy of the inferable
requirements and no sync test: 22 in-house entries do not justify two sources
of truth. `Pack.conflictsWith` is finally read, through the same engine.

### 4.2a What phase 2 actually built (2026-10-19)

- **A separate type, not new `RuleCapability` cases.** `RuleCapability` is the
  rule-to-rule graph (one rule provides a layer or Hyper, another consumes it).
  Adding backend needs there would have made the prerequisite flow look for a
  *collection* that "provides media keys". So `RuleEnvironmentNeed`
  (KeyPathRulesCore) holds `emits(key:)`, `capsLockInput`, `deviceTargeting` and
  `externalApp(name:path:)`, and `RuleCollectionNeedsExtractor` (AppKit, beside
  `RuleCollectionDependencyExtractor`) infers them from
  `KanataConfiguration.effectiveMappings` — so configuration-driven families count —
  including system actions and dual-role tap/hold outputs.
- **`unmet(_:profile:)`** evaluates needs against `BackendCapabilityProfile`: keys
  via `canEmit`, device targeting via `supportsDeviceTargeting`, Caps input is met
  by managed Caps on the session backend, external apps by file presence.
  `RuleCollectionCatalog.driverlessUnavailableReason` now uses this, so there is
  one inference path.
- **Declarations, per decision 3:** no catalog collection has a non-inferable need
  today, so no `requires` field was added to `RuleCollection`. `Pack.requires`
  exists and holds exactly one entry, KindaVim's app. A test forbids declaring an
  inferable need on any pack.
- **Accessibility was dropped** from the list in §4.2: the driverless runtime needs
  Accessibility for every rule, so a per-rule need would never tell anyone anything.
- **`conflictsWith`** is read (`PackDependencyChecker.conflicts(for:installedPackIDs:)`,
  both directions). No caller uses it yet; phase 3's engine turns it into verdicts.
  `PackInstaller.enforcePreInstallGates` still performs the KindaVim app check until
  phase 4 switches it to the engine.

### 4.3 Claims: one model for every "I want this key"

```swift
public struct Claim: Hashable {
    public enum Kind { case intentional, structural, reserved, activator(target: Layer) }
    public let key: KanataKey
    public let layer: RuleCollectionLayer
    public let kind: Kind
    public let owner: ClaimOwner      // .collection(id), .customRule(id), .pack(id), .leaderKey,
                                      // .chordGroup(name), .appKeymap(bundleID), .capsIntermediate, .foreignApp(name)
}
```

Every source produces claims: collections and custom rules (effective
mappings, as `detectConflicts` already computes), the leader key, chord groups,
aliases, app keymaps, **and** the backend's `reservedInputs` (the Caps
intermediate key, Raycast's Caps mapping). Two claims conflict when they share
`(key, layer)` and the kinds are incompatible under ADR-039 principle 3
(intentional beats structural automatically; intentional vs intentional,
anything vs reserved, and activator vs activator with different targets need
the user). This absorbs `conflictInfo`, `detectConflicts`, the dedupe
mismatch, `enforcePreInstallGates`, and `SessionCapsMappingPolicy`'s
`capsAlreadyMapped`/`f18Collision` into one comparison with one identity
(stable ids, never names).

### 4.4 `AdmissionEngine` — one pure function, one result type

```swift
public struct AdmissionEngine {
    public func admit(_ proposal: RuleProposal,            // the change being considered
                      into state: RuleState,               // enabled collections, rules, packs, leader…
                      profile: BackendCapabilityProfile) -> AdmissionResult
}

public struct AdmissionResult {
    public let verdicts: [Verdict]
    public var isAdmissible: Bool
}

public struct Verdict {
    public enum Severity { case blocking, needsChoice, automatic, advisory }
    public let severity: Severity
    public let subject: ClaimOwner                 // which rule/collection/pack this is about
    public let reason: Reason                      // .conflict(with:), .unsupported(capability), .reserved(key, by:),
                                                   // .missingPrerequisite(cap), .losesDependent(id), .requiresPermission
    public let fixes: [Fix]                        // .disable(id), .skipKeys([key]), .enable(provider), .openSettings(pane),
                                                   // .lower(to: Adapter), .chooseKey(candidates)
}
```

Callers, all through this one function:

| Caller | Today | After |
|---|---|---|
| Rule editor (Mapper, custom rule) | `CustomRuleValidator` + first-hit `conflictInfo` | inline advisory as the user types: "F18 is reserved for Caps Lock", "volume-up isn't available with the current backend" |
| Collection toggle | `conflictInfo` → `RuleConflictResolutionDialog` | `needsChoice` verdicts → one dialog |
| Pack install | `driverlessUnavailableReason` + hard-coded gates + silent auto-resolve | **preview** of every verdict before commit (ADR-039 §5, #375) |
| Catalog update | `combinedCatalogUpdateConflict` | same engine |
| Save | `detectConflicts` → `MappingConflictResolutionDialog` | same engine; reaching a *new* blocking verdict here is a bug and is logged as such (ADR-039 §2) |
| Startup / reload | Rust refusal re-wrapped three times | engine runs on the persisted state first; Rust refusal only if the engine passed, and then attributed (§4.6) |
| CLI `keypath doctor` (#1306) | permissions and runtime only | lists every blocking verdict with its subject and fixes |

### 4.4a What phase 3 actually built (2026-10-19)

- **No public `Claim` type yet.** Conflicts come straight from
  `RuleCollectionDeduplicator.detectConflicts` (today's authoritative detector), so
  phase 3 matches current behaviour by construction; golden tests pin that. A
  separate claims model would only pay off once phase 4 replaces the toggle-time
  `conflictInfo` and the silent `dedupe`, so it is deferred to then.
- **Attribution:** the detector reports display names, which are not unique; the
  engine maps each back to every enabled owner with that name (collection or custom
  rule id) and keeps the name only for synthetic parties (leader key, chord group).
- **`AdmissionVerdict`** carries severity (`automatic` < `advisory` < `needsChoice`
  < `blocking`), a subject, a reason and fixes. Reasons: `conflict`, `unmetNeed`,
  `reservedKey`, `capsLockHeldByOtherApp`, `packConflict`.
- **Reserved key (decision 1):** a rule using the live Caps intermediate as input or
  output is `automatic` with `moveCapsIntermediate(candidates:)`, the F13–F20 keys
  no rule uses and no other app holds; `blocking` only when none is free.
- **Inputs the caller supplies:** the live intermediate, intermediates other apps
  occupy, and a foreign Caps owner (all known to the Caps lease code at runtime).
- **Not called by anything.** Phase 4 switches callers; until then nothing a user
  sees changes. Phase 4 is where to decide how to surface conflicts the silent
  `dedupe` has been hiding on existing profiles (§ risks: one-time advisory).

### 4.4b Phase 4a (2026-10-19)

- `RuleCollectionsManager.conflictInfo(for:)` (collection and custom-rule forms) now
  asks `AdmissionEngine` on the proposed state instead of its own first-hit scan.
  Toggle time and save time therefore share one detector, one identity (ids) and
  one layer rule; the custom-rule-vs-custom-rule cross-layer false positive is gone.
  Neovim Terminal stays exempt, as the save path already drops it from the config.
- Synthetic parties (leader key, chord group) are not offered at toggle time (there
  is nothing to disable); the save path still refuses them. 4b renders them.
- `RuleCollectionDeduplicator.dedupe` still drops a second claimant (block builders
  rely on uniqueness) but now logs it as an admission gap, not at debug (ADR-039 §1).
- No migration or one-time advisory: there are no real users yet.

### 4.4c Phase 4b (2026-10-19)

- `AdmissionVerdictPresenter` words every verdict once (title, explanation, options
  from its fixes; `oneLine` for automatic verdicts). Dialogs, toasts and the CLI
  render from it.
- The save-time dialog (`MappingConflictContext`) is now built by
  `RuleCollectionsManager.mappingConflictContext(for:)` from the engine's conflict
  verdicts of the failing state, attributed by id. Custom rules are offered as
  options too (previously collections only, matched by non-unique name). It falls
  back to the plain explanation only when nothing can be turned off.
- `RuleConflictInfo.Source.named` lets the toggle-time dialog show a synthetic party
  (leader key, chord group): it explains, and hides "Switch to", since nothing can be
  disabled from there.
- The unused `ConflictResolutionDialog` is deleted. `RuleConflictResolutionDialog`
  and `MappingConflictResolutionDialog` keep their distinct choices (keep/switch vs
  pick-one-to-disable) but share the presenter's wording.

### 4.4d Phase 4c (2026-10-19)

- `PackInstaller.admissionPreview(for:manager:)` evaluates the engine on the state
  an install would produce (the pack's collection or managed collections enabled,
  its rendered rules added, its id among the installed packs) and keeps the
  verdicts that involve the pack. `PackInstallPreview` classifies them and lists
  what could be turned off (rules, custom rules by id) or removed (packs).
- `install(..., admission:)`: `.checked` proceeds only when the preview needs no
  confirmation and otherwise throws `needsReview(preview)`; `.confirmed(...)`
  applies the user's choices (removing packs first, disabling collections through
  the existing `additionalCollectionIDsToDisable`, custom rules in memory) and
  refuses anything still blocking; `.unchecked` keeps the old pack-wins behaviour
  for guided onboarding and programmatic callers (default, so existing callers
  and tests are unchanged). Both UI paths (Pack Detail, the Rules tab) use `.checked`.
- `PackInstallPreviewSheet` is the preview (ADR-039 §5): every offered resolution
  on by default so one click still installs; a block with no local fix (missing
  app) shows a link and disables Install. Automatic resolutions become a one-line
  note after a one-click install.
- The KindaVim ↔ Vim Navigation mutex moved from code into the registry
  (`conflictsWith`), and the KindaVim app requirement comes from `Pack.requires`;
  `enforcePreInstallGates` keeps only the retired-collection check and the
  old-order gates for unchecked installs.

### 4.4e Phase 4d (2026-10-19)

- **The live Caps environment reaches every evaluation.** `AdmissionEngine.Environment`
  (reserved intermediate, occupied candidates, foreign Caps owner) is published by the
  lifecycle coordinator at each session start — the same pass that reads other apps'
  `UserKeyMapping`s and, now, `capsConflict(on:)` — through `onAdmissionEnvironment`
  into `RuleCollectionsManager.admissionEnvironment`. Every `State` the manager, the
  resolver and `PackInstaller.admissionPreview` build goes through
  `admissionState(collections:customRules:installedPackIDs:)`, so toggle, editor save,
  conflict dialog and pack preview see one answer. Before the first start it is
  `.unknown` and the engine behaves as in phases 1–3; the runtime's own re-pick at
  reload (`SessionCapsRuntimeSupport.admit(rechoose:)`) remains the backstop.
- **The editors ask before writing.** `RuleCollectionsManager.reviewAdmission(forProposed:)`
  / `(forEnabling:)` return an `AdmissionReview`: the first blocking verdict as a
  sentence (`refusal`) and the automatic ones as notes. Conflicts are excluded — they
  keep the dialog from 4b. The Mapper refuses with the reason and writes nothing; after
  a save on the reserved key it says "✓ Saved. … Caps Lock will use F19 instead."; the
  inline custom-rule editor shows the refusal as its error; the Rules tab toggle refuses
  with a toast and, after an enable, toasts the note. The presenter's foreign-owner
  sentence no longer repeats the owner ("Turn that off first"), since the runtime names
  an unknown one "Another app".
- **Reserved key → #1307's re-pick (decision 1).** The engine's `.moveCapsIntermediate`
  candidates are in `SessionCapsIntermediate.pool` order, the order `choose` walks, so
  the key the note names is the key the next session start reserves; a test pins the two
  together. Nothing moves at save time: the save reloads, the reload restarts admission,
  and `chooseCapsSelection` saves the moved selection — the move already existed, 4d
  only predicts it to the user. All of F13–F20 taken is the one blocking case.
- **The catalog reason is the engine's sentence.** `RuleCollectionCatalog.driverlessUnavailableReason`
  evaluates the collection alone (`fileExists` answered true: companion apps are an
  install/toggle-time question with the user's real files) and renders the first
  `unmetNeed` through the presenter, so the gallery row, the rules list and the toggle
  say "… sends volu, which the current backend can't send" rather than a fixed media
  string. The system-action picker keeps `driverlessMediaUnavailableReason` for its
  own greyed buttons.
- Tests: `AdmissionEnvironmentTests` (environment plumbing, reserved-key note, re-pick
  parity, exhausted pool, foreign owner, unsupported output naming the key, conflicts
  left to the dialog, catalog sentence, Mapper refusal writes nothing) and a preview
  case for a pack on the reserved key.

### 4.5 Lowering: intent in rules, backend output in the generator

Rules keep expressing intent (`volu`, `caps` → Hyper, "this keyboard only").
A new generator stage, `Lowering`, maps each intent to what the active profile
supports:

| Intent | `session` profile | `driverKit` profile |
|---|---|---|
| consumer key output | `.viaAdapter`: `push-msg "media:volume-up"`, posted by the app as an `NSSystemDefined` event (pending the media-keys spike's measurements of repeat and external-display brightness) | native key |
| Caps Lock input | HID lease to a free intermediate key (#1307/#1309), `caps` rewritten to that key in `defsrc` | native `caps` |
| device targeting | unsupported → blocking verdict, never emitted | `macos-dev-names-*` |
| layer transparency under managed Caps | computed real fall-through value per key, with an advisory verdict naming keys whose behaviour changed | `_` |

The generator's `validKanataPassthrough` becomes a check against
`profile.outputUsages` plus the adapter table, so it cannot pass a key the
profile lacks.

### 4.6 Bridge validation stays, with attribution

The Rust check remains the backstop. The generator emits a side table
`[configLine → ClaimOwner]` (it already tracks mapping provenance for the
overlay inspector); when Rust rejects, the bridge returns the offending
`defsrc` key or action, and Swift maps it to a `Verdict` with a subject. The
four wrapper messages collapse to one renderer of `Verdict`.

### 4.7 Reserved-key registry

`profile.reservedInputs` is filled at runtime from: the chosen Caps
intermediate (every interface of the chosen keyboard, per #1309), other apps'
hidutil `UserKeyMapping`s (named, as #1307's banner does for Raycast), and any
future stand-ins. The editor, toggle and doctor all see them as `.reserved`
claims, so "F18 is in use by Caps Lock" is said before a save, not after a
session fails to start. **Policy (decided 2026-10-19): a user rule that takes
the current intermediate moves the intermediate**, as #1307 does at runtime:
the verdict is `automatic` with fix `.chooseKey(candidates:)` and an advisory
naming the new key. It blocks only when all of F13–F20 are taken.

## 5. What this gives each current need

- **Media keys.** The spike decides *whether* the session backend gets
  `consumerOutput: .viaAdapter`. Either way the catalog's media Function Keys
  entry stops being special-cased: it declares `consumerOutput`, the engine
  admits it or explains why not, and the function/media mode toggle becomes a
  normal admissibility question instead of a hard-coded flag. **Policy
  (2026-10-19):** with `consumerOutput: .none` the media entry is shown
  disabled with the reason; with `.viaAdapter` it is available and the mode
  toggle is the opt-in.
- **Caps Lock on multi-interface keyboards.** #1309's lease is unchanged; the
  intermediate key becomes a reserved claim visible everywhere, and
  `capsAlreadyMapped` becomes a verdict naming the other app.
- **Catalog capability.** Declarations plus the inferred==declared test make
  the catalog self-describing; a backend switch is a profile change, and
  "can this run here?" has one answer for the gallery, the toggle, the CLI
  and the installer.
- **Conflicts.** One detector, one identity, one dialog model; the pack
  `conflictsWith` field and ADR-039 §5 preview finally have an engine to run
  on; silent dedupe becomes an `automatic` verdict that is logged and shown
  in the post-install summary.

## 6. Phased plan

Each phase is one PR with its own tests; none changes user-visible behaviour
until phase 4.

| Phase | Scope | Tests |
|---|---|---|
| **1. Profile** — *done (see §4.1a)* | Bridge answers "can this backend emit key K" with the session output rule; Swift `BackendCapabilityProfile` asks it; `SystemActionInfo.isSupportedInDriverlessSession`, `FunctionKeyMode.isSupportedInDriverlessSession` and `RuleCollectionCatalog.driverlessUnavailableReason` derive from it. | Rust rule test; bridge-backed test that every former list gives the same answer; prefix, fallback, backend and cache tests. |
| **2. Requirements** — *done (see §4.2a)* | `RuleEnvironmentNeed` (emits key, Caps input, device targeting, external app) inferred from effective mappings; `unmet(_:profile:)` checks them; `Pack.requires` for KindaVim; `conflictsWith` read in both directions; the catalog check now uses the same inference. | Whole-catalog test against the real bridge; system-action and tap/hold inference; device targeting per backend; packs declare only non-inferable needs; conflictsWith both ways. |
| **3. Claims + engine** — *done (see §4.4a)* | `AdmissionVerdict` (KeyPathRulesCore) and `AdmissionEngine` (AppKit): conflicts from `detectConflicts` attributed to ids, unmet needs, reserved Caps intermediate (moves automatically), another app holding Caps, pack conflicts and requirements. Not called yet. | Golden scenarios match today's detector; attribution to ids; media blocking per backend; intermediate move/block; foreign Caps owner; packs; a fresh profile admits with zero findings against the real bridge. |
| **4. Callers** — *in progress: 4a–4d done; 4e startup/CLI to follow* | toggle, rule editor, pack install (conditional preview, see §7), catalog update, save and startup call the engine; `conflictInfo`/`dedupe` divergence removed; the dead `ConflictResolutionDialog` deleted; the dialogs render `Verdict`. | UI tests per caller; pack install preview snapshot; "save reaches a new blocking verdict" logs an error (and the existing test guardrail catches it). |
| **5. Attribution** | config-line → owner side table; Rust returns the offending element; one message renderer. CLI `doctor` lists verdicts. | end-to-end: a rule with `volu` names itself in the refusal; CLI output contract test. |
| **6. Lowering** | adapter table in the generator; media via push-msg if the spike approves; computed fall-through under managed Caps. | generator goldens per profile; fall-through advisory test. |

Phases 1–3 are additive and can land before #1304–#1309 merge; 4–6 should
follow them.

## 7. Decisions (Micah, 2026-10-19)

1. **Reserved key.** A rule that takes the Caps intermediate key **moves the
   intermediate** (automatic verdict plus advisory); it blocks only when no
   candidate is free.
2. **Media keys.** In the catalog, opt-in through the mode toggle when the
   profile supports consumer output (natively or via adapter); shown disabled
   with the reason when it does not.
3. **Requirements.** Infer everything derivable from mappings and actions;
   declare only non-derivable needs in an optional `requires`; no duplicate
   declarations and no sync test.
4. **Pack installs.** One click when the engine finds nothing that changes
   what the user already has. A preview with choices **only** when a verdict
   is `needsChoice` or `blocking`. Automatic structural resolutions produce a
   one-line post-install summary, never a dialog.
