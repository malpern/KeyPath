# Community Collections Plan (KeyPath)

## Purpose

KeyPath’s primary audience is **power Mac users who have never used a remapper** and are coming from basic launcher-style workflows. This plan defines how we can also bring along the existing macOS Kanata user base while keeping development effort contained, by evolving “Rule Collections” into a **community-shareable, curated system** with an in-app configuration UX that substantially improves on Karabiner-Elements’ community experience.

## Constraints / Non-goals

- **No Kanata config parsing as an input API**: avoid building a shadow Kanata parser/interpreter. Prefer one-way generation (see ADR-023 and ADR-025).
- **No general importer/converter** of arbitrary `.kbd` files into internal rule models.
- **Community collections are not directly editable** (decision): users can enable/disable and change exposed parameters, but do not edit the authored mapping definition in-app.
- **Config generation remains centralized** and validated before writing.

## Glossary

- **Collection Definition**: authored, versioned, shareable rule collection (what the community contributes).
- **Collection Instance / User State**: user-owned state for a definition (enabled, parameter selections, etc.).
- **Pack**: a bundle of one or more Collection Definitions + metadata (distribution unit).

## Current System (as implemented today)

### Data model

`RuleCollection` currently mixes:
- **Definition data**: name, summary, category, tags, icon, target layer, mappings.
- **UI schema + user state**: `displayStyle` and style-specific fields (e.g. `selectedOutput`, `homeRowModsConfig`).

Configurable collections exist today via:
- **`.singleKeyPicker`**: `presetOptions` + `selectedOutput`
- **`.tapHoldPicker`**: `tapHoldOptions` + `selectedTapOutput` / `selectedHoldOutput`
- **`.homeRowMods`**: `homeRowModsConfig`

Some collections are **computed at generation time**:
- Home Row Mods generates `KeyMapping`s from `HomeRowModsConfig`.
- Tap-hold picker generates dual-role behavior from selected tap/hold.

### Persistence and generation flow

- **Built-in definitions**: `RuleCollectionCatalog`
- **User persistence**: `RuleCollectionStore` saves `RuleCollections.json` (and `CustomRulesStore` saves custom rules)
- **Orchestration**: `RuleCollectionsManager` updates state, warns on conflicts, and regenerates configuration
- **Generation + validation**: `ConfigurationService.saveConfiguration(ruleCollections:customRules:)` → `KanataConfiguration.generateFromCollections(...)` → validate → write `.kbd`

### Current upgrade behavior (risk)

`RuleCollectionCatalog.upgradedCollection(from:)` currently preserves only `isEnabled` when replacing a stored built-in with an updated catalog version. This can overwrite user selections such as:
- Leader key choice (if represented via collection state)
- Caps Lock tap/hold choices
- Home Row Mods timing and assignments

This must be addressed before community packs exist.

## Lessons from Karabiner-Elements Community (opportunities)

### What works
- **Simple distribution**: rule bundles are easy to share and import.
- **Composable rules**: many small rules mix-and-match well.
- **Simple vs complex**: a two-tier mental model reduces intimidation.

### Pain points to avoid
- **Discoverability outside the app** (web/repo → download → import → find rule).
- **Non-configurable “complex rules”**: many require editing JSON or choosing among dozens of near-duplicates.
- **Trust and safety ambiguity**: unclear what a downloaded rule does, what keys it takes over, and how to undo.
- **Debugging is expert-only**: hard to map “behavior” back to “which rule caused it,” or to diagnose failures.
- **Rule sprawl**: too many variants with minor parameter differences.

### KeyPath’s UX advantage to target
- Community rules should be **configurable in-app** via SwiftUI controls (no JSON editing).
- One flow: **browse → preview → install → configure → test → rollback**.
- Explainability: show **affected keys, outputs, conditions, conflicts**, and a “what changed” preview.

## Foundations Roadmap (Phased Plan)

## Phase 0 — Inventory + ownership boundaries (this document’s immediate scope)

### Phase 0 decision: collections are not editable

Community/built-in collections are treated as **immutable definitions**. Users can:
- enable/disable
- change exposed parameters (pickers/toggles/sliders)
- add Custom Rules for bespoke behavior

Users cannot directly edit a collection’s base mapping definitions.

### Phase 0 deliverables

1) **Current system map (1–2 pages)**
- A concise diagram/description of Catalog → Store → Manager → Generator → Validate → Write.
- Identify which collections are static vs computed.

2) **Field ownership matrix for `RuleCollection`**
For each field: owner (definition vs user), persisted across upgrades, merge strategy.

Initial draft (to be finalized):
- **User-owned (preserve on upgrade)**
  - `isEnabled`
  - `selectedOutput` (singleKeyPicker)
  - `selectedTapOutput`, `selectedHoldOutput` (tapHoldPicker)
  - `homeRowModsConfig` (homeRowMods)
  - (If leader key is represented as a collection parameter) the leader selection value

- **Definition-owned (overwrite from updated definition)**
  - `name`, `summary`, `category`, `icon`, `tags`
  - `displayStyle`
  - `pickerInputKey`
  - `presetOptions`, `tapHoldOptions`
  - `targetLayer`, `momentaryActivator` (definition semantics)
  - `mappings` (immutable definition; user does not edit)

3) **Upgrade clobber scenarios + fix requirements**
Write 3–5 concrete “user annoyance” cases (e.g., “Caps tap/hold reset after update”) and translate them into explicit merge rules.

4) **Phase-1 invariants**
- Updating definitions must never overwrite user-owned state.
- Stable IDs and explicit versions are required for definitions.
- Config generation remains centralized and validated before write.
- Conflicts are deterministic and surfaced clearly.

### Phase 0 key open question (recorded as default assumption)

**Leader key model**
- Default assumption: treat the leader key as a **global user setting** (or a dedicated system collection that stores only user-owned selection), not per-collection custom activator edits.
- Per-collection activator customization is deferred; it complicates merge semantics and UX.

## Phase 1 — Separate Definition from User State (merge-safe upgrades)

### Objective
Create an explicit conceptual split:
- `CollectionDefinition` (immutable, versioned)
- `CollectionInstance` / user state (enabled + parameter values)

### Requirements
- Built-in upgrades preserve user state (not just `isEnabled`).
- Persist user state independently of the definition so packs can update safely.

## Phase 2 — Define “Pack” format + limited UI schema (community-ready)

### Objective
Introduce a shareable pack unit that reuses existing UI styles to keep effort low.

### Principles
- Avoid a general “form builder.”
- Only support a small number of parameterized UI styles already proven:
  - list/table (display-only)
  - single key picker
  - tap-hold picker
  - (optional) home row mods (may remain built-in only initially)

### Pack contents (proposed)
- `pack.json`: id, name, author, license, version, homepage, minimum KeyPath version.
- `collections/*.json`: definitions + parameter schema (limited).
- `assets/`: optional icons/screenshots.

## Phase 3 — Move built-ins onto the same pipeline as packs

### Objective
Built-in collections should be “just a bundled pack” so:
- one loader path exists
- contributions mirror the built-in model
- behavior stays consistent and testable

## Phase 4 — Distribution model (start simple, scale later)

- **V1**: import/export packs from disk (folder/zip).
- **V2**: curated registry hosted on GitHub (index JSON + hashes), browsable in-app.

Trust features (to surpass Karabiner UX):
- provenance (source URL, author, license)
- integrity (hash)
- changelog / version history

## Phase 5 — UX features that substantially improve on Karabiner-Elements

Pick a small set of “big wins”:
- **Configurable community rules in-app** (no JSON editing).
- **Preview/explainability**: affected keys, outputs, conditions, and a “what will change” view.
- **Conflict visibility**: explicit key-level conflict list; deterministic priority explanation.
- **Debuggability for non-tech users**: “why didn’t this work?” checks + “recently triggered rule” timeline.
- **Safe experimentation**: try-mode + one-click rollback to a known-good baseline.

## Phase 6 — Contribution workflow and curation

- Contributor guide: required metadata, screenshot/description requirements, QA checklist.
- CI validation for packs: schema, required fields, versioning rules.
- Curated “official community packs” repo with review gates.

## How this supports Kanata migration with low dev effort

This plan is compatible with a BYOC (Bring Your Own Config) lane:
- Existing Kanata users can keep their config untouched.
- Community collections serve the broader audience and provide a “graduation path” from BYOC into KeyPath-managed, shareable, configurable collections.

