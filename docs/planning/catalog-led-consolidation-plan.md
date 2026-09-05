# KeyPath: catalog-led consolidation execution plan

Date: 2026-09-04
Status: approved direction; Phase 0 inventory recorded; Phase 1 persistence/recovery foundation implemented, operation migration still open.
Baseline: `master` at `a12bb07d5`; recheck code, branches, and issues before implementation.

## Outcome

Keep KeyPath and improve it incrementally around this promise:

> Discover useful keyboard customizations, understand them, enable them safely,
> and manage them through an excellent catalog and visual editor.

Preserve the catalog as a primary discovery and management surface. Reduce new
commitments around ecosystem compatibility and secondary products. Make existing
behavior easier to reason about before adding more capabilities.

This plan authorizes no automatic deletion of existing features or user data.
Implementation is authorized, subject to the UI discussion gate below; this is
not authorization for a public release.
Feature retirement requires a concrete compatibility and migration proposal;
freezing expansion does not require turning off existing functionality.

## Product scope

| Area | Decision for this program | Boundary |
| --- | --- | --- |
| Catalog | Keep and improve | Browsing, search, previews, explanations, enable/disable, customization, active state, and pack management remain core. |
| Remapping and layers | Keep and improve | Basic remaps, tap-hold, home-row mods, layers, and useful existing presets. Preserve other working catalog entries while auditing their support cost. |
| Keyboard visualization | Keep | Accurate physical layouts, logical labels, active mappings, and useful feedback. |
| Setup and runtime | Keep and harden | Permissions, driver/service integration, emergency stop, recovery, updates, and safe config changes. |
| App/URL launching and window actions | Keep bounded | Useful catalog actions; no general workflow engine expansion. |
| Karabiner import | Freeze expansion | Inventory supported conversions and explain unsupported cases. Defer full parity, Goku, and AI-assisted conversion. |
| Kanata UI coverage | Drop completeness as a goal | New capabilities require a specific user workflow, catalog/editor design, conflict policy, and verification plan. |
| AI configuration and repair | Defer expansion | Inventory existing entry points. Prefer deterministic validation and recovery; evaluate retirement separately. |
| Insights/analytics | Defer expansion | Consider narrowly useful mapping-tuning feedback separately from a standalone analytics product. |
| Hardware integrations | Defer expansion | Keep practical layout support. Defer keyboard display protocols and exhaustive QMK keymap conversion. |
| Cinematic onboarding/rendering | Freeze expansion | Keep working visuals and fix regressions; no new rendering systems in this program. |
| OS integrations | Defer speculative features | Continue compatibility work; defer speculative Siri/entity-schema integrations. |

Do not equate a catalog entry with a requirement to expose every related engine
option. Do not remove working entries merely because their underlying capability
appears on the deferred-expansion list.

## Intended shape of the app

Use this journey to judge changes, without prescribing a navigation redesign:

1. Discover a customization in the catalog.
2. Understand its effect, prerequisites, and affected keys.
3. Enable it with a predictable conflict decision.
4. Customize the same item in its editor.
5. See whether it is active, saved for later application, or needs attention.
6. Disable or remove it with an understandable effect on dependent items.

Catalog details, installed state, editor state, and overlay should describe the
same customization. Pack ownership must be explicit rather than inferred from
special-case names or settings. Supporting bundles must not silently expand into
a general package-management system.

## Execution rules

- Discuss significant UI changes with Micah before implementation. Bring concrete
  before/after interactions and tradeoffs for navigation, catalog organization,
  conflict dialogs, pack ownership controls, configuration modes, or material
  status presentation changes. Internal work and regression fixes can proceed;
  approval of this plan is not advance approval of those UI decisions.
- One bounded behavior or compile boundary per implementation PR. Each phase
  must leave a usable app; no long-lived replacement application.
- Preserve existing configuration formats and stable identifiers by default.
- Extend canonical owners before inventing services or broad protocols. Delete
  replaced forwarding paths as consumers migrate.
- Keep runtime readiness distinct from registration and from pending approval.
- Keep installer/lifecycle work through the existing canonical facades.
- No blanket singleton migration, manager merger, installer rewrite, or Kanata
  engine replacement. Follow [ADR-043](../adr/adr-043-opportunistic-manager-consolidation.md).
- Follow repository worktree, review, CI, merge, and deploy policy. This planning
  document does not override those gates.

## Phase 0 — Establish the scope and behavioral baseline

Owner: implementing engineer, with Micah deciding product tradeoffs.

Work:

- Inventory user-facing capabilities: entry point, implementation owner,
  supported configuration types, tests, compatibility obligations, and scope
  disposition from the table above. Record unknown usage rather than assuming
  an obscure feature is unused. Do not add telemetry for this exercise.
- Map every configuration mutation: catalog enable/disable, collection editor,
  mapper, pack install/remove, CLI, raw/generated saves, and external file edits.
- Record existing success/failure semantics, persistence order, reload count,
  observer timing, and restoration behavior for each path.
- Inspect existing work before duplicating it, especially
  `codex/module-split-spike` and setup/UX branches listed by `git worktree list`.
  Branch existence is not evidence of readiness or permission to adopt it.
- Recheck test infrastructure. On September 4, coverage run 33874656723 stopped
  before tests at the runner disk-reserve check. Restore a usable test baseline
  through the normal infrastructure workflow; do not lower the reserve to hide it.

Deliverables: feature disposition matrix, mutation-path matrix, representative
configuration fixtures, and baseline test/behavior evidence.

Exit gate: every mutation entry point has an owner and recorded behavior; core
journeys can be exercised; unresolved infrastructure/physical-input verification
gaps are named. No claim that the entire app is healthy based on test counts.

## Phase 1 — Make configuration changes one reliable operation

First implementation milestone; do this before a broad module split.

Initial evidence: the collection callback discarded reload results while
`SaveCoordinator` classified them. PR #1264 now retains the original result
through that boundary. The compatibility Boolean still means persisted, not
applied; changing it awaits recovery across the entire operation.

Proposed PR sequence:

1. Define and test one result contract using existing reload dispositions:
   applied, saved/pending, rejected, and failed. Define cancellation and recovery
   failure explicitly. Trace state through async boundaries and callbacks.
2. Route collection and mapper mutations through one transaction owner, extending
   `SaveCoordinator` or the current canonical owner where practical. Serialize
   commits; prevent stale completions from overwriting newer edits.
3. Include source stores, generated files, and affected preferences/pack metadata
   in a consistent commit/recovery design. Preserve a recoverable prior revision
   before changes; define startup recovery for interruption between writes.
4. Route catalog/pack and CLI operations through the same application contract.
   Adapt raw saves and external edits to the same result/recovery semantics while
   preserving their different ownership rules. Remove replaced mutation paths.

Acceptance criteria:

- All surfaces distinguish saved/pending from applied; no unconditional applied
  indication when reload fails or runtime is unavailable.
- Validation rejection leaves prior committed state intact. Persistence failure,
  cancellation, and reload failure have deterministic recovery across stores,
  files, and runtime. Recovery failure is visible, never reported as success.
- One logical internal edit produces one reload attempt, except explicit recovery
  actions. Watcher suppression cannot lose a concurrent external edit.
- Observers see a consistent revision. Rapid edits and interrupted multi-file
  writes cannot silently leave the UI, stores, and active configuration disagreeing.
- Tests inject these failures using temporary stores and a controllable engine;
  signed installed-app checks verify representative actual remaps and reloads.

Update [configuration-save-pipeline.md](../architecture/configuration-save-pipeline.md)
to the implemented contract, and add a durable bug/ADR record for verified findings.

## Phase 2 — Make catalog management consistent

Depends on Phase 1's result contract. Product decisions can be prepared in Phase 0.

Work in separate PRs: shared conflict policy, explicit pack ownership, then
consistent catalog/editor/overlay state and wording.

- Choose one conflict policy with a preview of displaced mappings; an explicit
  overwrite action may differ from an ordinary enable, but the entry surface
  alone must not change semantics. Preserve intentional CLI options explicitly.
- Decide behavior when multiple packs want the same collection, and when a user
  customizes a pack-managed collection. Micah reviews concrete examples before
  implementation. Do not silently select a winner or expand ownership features.
- Keep entry identity stable between discovery and management; distinguish
  installed, enabled, and successfully applied state where they differ.
- Explain forward prerequisites and consequences of disabling providers. Preserve
  user customizations during pack removal and restoration.

Exit gate: the core discovery-to-disable journey works from the visible UI;
catalog and editor operations yield equivalent results; open surfaces refresh
consistently; pack removal and conflicts preserve the agreed user choices.
Update user guides and accessibility identifiers for changed interactions.

## Phase 3 — Separate nonvisual behavior from the app

Depends on Phase 1; do not move unstable save semantics between modules first.

Target responsibilities (not a mandate to create five new modules):

| Responsibility | Direction |
| --- | --- |
| Rule models and constraints | Build on `KeyPathRulesCore`. |
| Configuration generation | Isolate deterministic generation from UI, live probes, and persistence. |
| Application operations | Reuse the transaction contract and focused services from app and CLI. |
| Runtime and installation | Preserve platform adapters and canonical evidence/lifecycle owners. |
| Presentation | Catalog, editors, overlay, and dialogs consume typed operations and state. |

First move pure generation with representative golden fixtures. Then remove the
CLI's broad `KeyPathAppKit` dependency where the actual command inventory permits.
Narrow `RuntimeCoordinator` consumers incrementally and move presentation choices
out of runtime orchestration. Review the existing module spike before proceeding.

Exit gate: rule generation tests run without app/installer initialization; shared
operations accept temporary storage and a fake engine; migrated consumers no
longer depend on the broad coordinator; replaced bridges are deleted. Record
dependency and test-scope improvements, not just smaller source files.

## Phase 4 — Clarify advanced configuration support and retire selectively

Prepare the managed/raw compatibility decision during Phase 0; implement it only
after save semantics are reliable. Do not silently migrate existing configs.

- Specify what KeyPath can edit and round-trip safely. For unsupported constructs,
  preserve original content and explain editing limits; require an explicit,
  backed-up conversion before any lossy transition to managed configuration.
- Review AI/Insights/import entry points for retention or retirement using the
  Phase 0 inventory. Remove expansion promises from the roadmap first.
- Each proposed retirement names the current users/workflows affected, data and
  configuration preservation, replacement or export path, guide changes, and
  rollback. Micah decides the proposal before feature deletion.
- Delete abandoned code and flags only after checking consumers and migrations.
  Do not remove external engine support merely because its UI expansion is deferred.

Exit gate: supported configuration modes have explicit behavior; no silent data
loss; deferred features are not presented as unfinished core promises; any actual
retirements have approved migration and recovery paths.

## Validation and completion

During iteration use targeted tests and the repository's fast workflow. Before a
code PR's final broad gate, synchronize with `origin/master`, check build
contention, run required tests/accessibility checks and review gate. Follow
[PR invariants](../process/agent-pr-invariants.md), including merge and post-merge
deployment requirements. A docs-only planning change needs document validation,
not an application rebuild.

Final acceptance journeys: clean setup to first remap; catalog discovery and
customization; conflicting pack enable/remove; rapid edits; unavailable runtime;
failed reload and recovery; external config edits; upgrade with existing configs;
disable/emergency stop; uninstall preserving config. Use the shared VM lab where
clean-machine verification is needed, and distinguish simulated input from
physical-HID evidence. Name installer state-matrix rows for affected lifecycle work.

Program completion means the catalog remains complete for the retained scope,
mutations share verified semantics, core behavior has enforceable nonvisual
boundaries, and the roadmap matches supported promises. No feature expansion is
needed to declare this consolidation successful.

## Backlog reconciliation and next action

Recheck issue state before editing; reuse existing issues instead of duplicating
them. Suggested mappings, not automatic closure instructions:

- #468 and #375: catalog pack ownership/conflict decisions in Phase 2.
- #888 and #1181: timing/activation and setup language consistency where touched.
- #604 and #747: test and signed clean-setup acceptance evidence.
- #855: installer responsibility split stays deferred unless a concrete lifecycle
  change requires it; it is not a prerequisite for this program.
- #213, #212, #211: conversion expansion remains deferred; no parity commitment.
- #204: inventory Insights and decide disposition, not an automatic completion task.

## Implementation checkpoint — September 5

Implemented slices (the table describes the merged state of this checkpoint):

| PR | Result | Remaining boundary |
| --- | --- | --- |
| #1260 | Mutation inventory and retained save reload results; unused alternative writer methods removed. | Other mutation surfaces still need migration. |
| #1262 | FIFO coordinator saves, operation-local file snapshots, queued cancellation and recursive callback protection. | Admission was extended to collection/pack/bootstrap paths by #1267–#1268; full runtime recovery still needs migration. |
| #1263 | Explicit previous-file, minimal-safe-file, and failed recovery outcomes retaining both errors. | File recovery does not assert source-store or engine restoration. |
| #1264 | Collection persistence and retry callbacks retain applied/pending/rejected/failed outcomes. | Compatibility Boolean continues to mean persisted. |
| #1265 | Durable journal for config plus both rule stores, startup recovery, external-change checks, and observers after file-set commit. | Preferences, pack metadata and runtime rollback remain outside this file transaction. |
| #1266 | Failed keymap writes restore the prior collection, manager preferences and attempted overlay selection, preserving unrelated layout preferences and newer display choices. | UserDefaults is not crash-atomic with the journal. |
| #1267 | Shared service admission before public collection/keymap mutation and across coordinator save/recovery, with explicit nested permits and callback rejection. | Pack/bootstrap admission was added by #1268; CLI operation ownership and external writers remain. |
| #1268 | Pack install/uninstall/settings and bootstrap hold shared admission across nested mutations, metadata and recovery. | CLI operation ownership and external writers still require migration; pack commits remain separate. |
| #1269 | Standalone regeneration, conflict retries, prerequisite application and snapshot restoration share admission with explicit nested permits. | Cross-instance/process ownership and whole-operation recovery remain. |
| #1270 | Direct service writes, journal recovery, trusted restoration and missing-file self-healing share admission. | CLI ownership, feature-specific writers, source/cache freshness and complete recovery remain. |
| #1271 | Per-user directory leases exclude cooperating services/processes, with cancellation, alias reentry protection and off-actor sentinel I/O. | CLI operation scope, cached state, external editors and cross-UID writers remain distinct boundaries. |

Admission now also holds a cooperative OS lease across service instances and
processes for the same directory. CLI configuration apply now holds admission
from source loading through reload; backup/restore also participate. CLI pack and
collection operations, external edits and stale cached app state remain separate
boundaries.
The first migrated persistence journey now has interruption and failure tests.
This is a useful foundation, not completion of Phase 1 or the program.

Next implementation sequence:

1. Complete feature-specific writers and CLI operation ownership, loading/reconciling current source and metadata state after admission;
   preserve explicit ownership through trusted nested calls, and reject recursive
   callback writes rather than allowing stale rollback or deadlock.
2. Keep the prior source revision through runtime classification and restore
   sources/preferences/metadata consistently after rejection or failure.
3. Replace time-only watcher suppression with recognition of actual internal
   revisions. Buffer during the write operation and reconcile external changes
   afterward. Cover atomic replacement, directory creation, overlapping edits,
   cancellation and stop/restart; do not use a longer blind suppression window.
4. Migrate remaining CLI/raw/pack paths, then move stable pure generation out of
   app dependencies. Do not start a broad module move while save ownership is
   still changing.

UI decisions awaiting Micah's discussion: consistent conflict confirmation with
an affected-key preview; saved/pending/recovery status wording in the existing
status area; and explicit pack ownership behavior. No navigation redesign,
feature removal or public release is authorized by this checkpoint.

Validation limits: supported-runner CI has passed the merged internal slices.
The local macOS 27 host retains four independently reproduced baseline snapshot
failures (three HomeRowTiming variants and RepairSettingsTabView). Signed,
notarized installation has passed. Earlier local checks encountered incomplete
Kanata setup; subsequent installed-CLI inspection reported `isOperational: true`
with no issues and a responding runtime. This is readiness evidence, not a
physical remap test. A managed macOS 15 lab guest installed the signed
#1265 artifact and opened the first-run screen; helper registration was denied,
and its newer Peekaboo bridge could read but could not advance setup reliably.
Artifacts were collected and the lease destroyed. This is not successful
first-remap, unmanaged-permission or physical-HID verification.

Runner storage: PR #1261 remains separate and unmerged until the actual CI
process has removable-volume permission and completes validation. Existing CI
can run above the disk reserve; do not lower that reserve or claim that external
storage migration is complete.
