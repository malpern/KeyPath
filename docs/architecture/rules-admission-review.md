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

### 4.2 Declared requirements on catalog entries and packs

Extend `RuleCapability` (`RuleDependencyGraph.swift:37`) from three cases to a
closed set, and let the catalog and packs *declare* it:

```swift
public enum RuleCapability: Codable, Hashable {
    case layerContent(layer), layerActivation(layer), keyAlias(.hyper)   // existing
    case consumerOutput              // media / brightness keys
    case capsLockInput               // remaps Caps Lock
    case deviceTargeting
    case accessibilityPermission     // push-msg window:* / system:*
    case reservedKey(HIDUsage)       // e.g. a mapping on F18
}
```

Catalog JSON gains an optional `requires: ["consumerOutput"]`. For existing
entries the extractor keeps inferring from mappings, and a **build-time test
asserts that inferred == declared** for every catalog entry, so declarations
cannot rot. `Pack.conflictsWith` is finally read, through the same engine.

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
session fails to start.

## 5. What this gives each current need

- **Media keys.** The spike decides *whether* the session backend gets
  `consumerOutput: .viaAdapter`. Either way the catalog's media Function Keys
  entry stops being special-cased: it declares `consumerOutput`, the engine
  admits it or explains why not, and the function/media mode toggle becomes a
  normal admissibility question instead of a hard-coded flag.
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
| **1. Profile** | Rust exports `BackendCapabilityProfile`; Swift decodes it; `SessionKeyMap`, `SystemActionInfo.isSupportedInDriverlessSession`, `FunctionKeyMode.isSupportedInDriverlessSession`, `driverlessUnavailableReason` and `validKanataPassthrough` read from it. Delete the deny-lists. | profile round-trip; every deleted list's former behaviour as an assertion against the profile; Rust test that `supported` ≡ "within profile". |
| **2. Declared requirements** | `RuleCapability` extended; `requires` in catalog JSON and `Pack`; extractor infers the new cases; **inferred == declared** test over the whole catalog. | catalog contract test; one failing case for a mis-declared entry. |
| **3. Claims + engine** | `Claim`, `Verdict`, `AdmissionEngine` in `KeyPathRulesCore`; implemented over the existing `detectConflicts` data so results are identical; reserved claims from the profile. | golden tests: every case `conflictInfo` and `detectConflicts` find today, the same verdicts; new cases for F18, media keys, foreign Caps mapping, app keymap vs global. |
| **4. Callers** | toggle, rule editor, pack install preview, catalog update, save and startup call the engine; `conflictInfo`/`dedupe` divergence removed; the dead `ConflictResolutionDialog` deleted; the dialogs render `Verdict`. | UI tests per caller; pack install preview snapshot; "save reaches a new blocking verdict" logs an error (and the existing test guardrail catches it). |
| **5. Attribution** | config-line → owner side table; Rust returns the offending element; one message renderer. CLI `doctor` lists verdicts. | end-to-end: a rule with `volu` names itself in the refusal; CLI output contract test. |
| **6. Lowering** | adapter table in the generator; media via push-msg if the spike approves; computed fall-through under managed Caps. | generator goldens per profile; fall-through advisory test. |

Phases 1–3 are additive and can land before #1304–#1309 merge; 4–6 should
follow them.

## 7. Open questions for Micah

1. **Scope of "reserved".** Should a rule be *blocked* from using the Caps
   intermediate key, or should choosing that key move the intermediate (as
   #1307 does at runtime)? The engine can do either; the second is friendlier
   but hides the reservation.
2. **Media adapter policy.** If the spike shows posting system-defined media
   events works, do we want `.viaAdapter` on by default, or opt-in per
   collection?
3. **Catalog declarations: required or inferred?** The proposal keeps both
   with a test that they agree. The alternative is inference only, which is
   less work and less explicit.
4. **Pack installs.** ADR-039 §5 asks for a preview; today installs
   auto-resolve silently. Is a mandatory preview acceptable for one-click
   installs, or should it be a summary afterwards?
