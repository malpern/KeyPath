# Auto Shift Symbols Conflict Analysis

This document records the product and overlap review for the experimental `Auto Shift Symbols` collection.

It exists to satisfy the collection review policy in:

- [COLLECTION_PR_REVIEW_CHECKLIST.md](docs/COLLECTION_PR_REVIEW_CHECKLIST.md)
- [COMMUNITY_COLLECTIONS_CONTRIBUTION_POLICY.md](docs/COMMUNITY_COLLECTIONS_CONTRIBUTION_POLICY.md)

## Problem and Audience

`Auto Shift Symbols` is for users who want fast access to shifted punctuation on the base layer without entering a symbol layer.

The collection is intentionally narrow:

- symbols only
- base layer only
- no separate activator
- timing-based behavior on the same key

This is distinct from Symbol Layer because the interaction model is different:

- Symbol Layer is modal or activator-driven.
- Auto Shift is per-key timing behavior.

## Why This Is a Separate Collection

This should not be implemented as a preset on the existing Symbol Layer collection.

Reason:

- Symbol Layer changes the active layer and remaps many keys at once.
- Auto Shift leaves the user on base and changes the behavior of a fixed set of keys.
- The overlap is partly in output intent, not in activation model or implementation model.

It is also narrower than a general-purpose tap-hold editor:

- fixed keyset
- fixed hold behavior of `S-<key>`
- simplified UX around timeout and fast-typing protection

## Claimed Surface Area

- Layer: `base`
- Activator: none
- Scope: global
- Claimed keys:
  - `` ` ``
  - `-`
  - `=`
  - `[`
  - `]`
  - `\`
  - `;`
  - `'`
  - `,`
  - `.`
  - `/`

Generated behavior:

- tap outputs the original key
- hold outputs the shifted variant
- optional `require-prior-idle` reduces accidental holds during typing streaks

See:

- [RuleCollectionCatalog.swift](Sources/KeyPathAppKit/Services/RuleCollectionCatalog.swift)
- [RuleCollectionConfiguration.swift](Sources/KeyPathAppKit/Models/RuleCollectionConfiguration.swift)
- [KanataConfiguration+MappingGenerators.swift](Sources/KeyPathAppKit/Infrastructure/Config/KanataConfiguration+MappingGenerators.swift)

## Overlap Analysis

### Symbol Layer

- Overlap type: `resolvable-by-redesign`
- Why:
  - there is output-intent overlap for punctuation
  - there is not direct key/layer overlap in runtime behavior because Symbol Layer lives on a separate layer with an activator
- Resolution:
  - keep Auto Shift scoped to symbols on base
  - position it as a timing-based alternative, not a replacement

### Home Row Mods

- Overlap type: `none`
- Why:
  - default Auto Shift scope does not claim alpha home-row keys
  - no shared activator

### Home Row Layer Toggles

- Overlap type: `none`
- Why:
  - Auto Shift does not claim alpha home-row keys
  - no shared activator

### Function Layer

- Overlap type: `mutually-exclusive` in specific key overlaps, otherwise `none`
- Overlap keys:
  - `;`
  - `,`
  - `.`
  - `/`
- Why:
  - both collections target base-level claimed keys on overlapping physical keys
  - enabling both produces a real runtime conflict
- Current runtime behavior:
  - generic conflict detection blocks the overlap
- Recommendation:
  - if this collection graduates from experimental, define explicit user-facing copy recommending the more intent-aligned collection

### Custom Rules On Base Layer

- Overlap type: `blocked-invalid`
- Why:
  - custom rules can claim any of the same punctuation keys
  - the runtime should block these collisions rather than attempt implicit merge behavior
- Current runtime behavior:
  - generic conflict detection blocks the overlap

### Tap-Hold Picker Collections

- Overlap type: `none` today
- Why:
  - current tap-hold picker collections do not claim the Auto Shift punctuation keyset
- Caveat:
  - future tap-hold collections that reuse these keys should be reviewed under this same policy

## Redesign Considered

Redesigns considered before shipping:

1. Extend Symbol Layer instead of adding a new collection.
   Rejected because the interaction model is different.

2. Add letters as well as symbols.
   Rejected for the first version because it increases typing-risk, overlap risk, and user-support burden.

3. Make the collection fully arbitrary and user-key-selectable.
   Rejected for the first version because it turns a simple built-in into a mini rule editor.

## User Experience Requirements

The collection should be explained as:

- experimental
- timing-based
- best for punctuation-heavy users
- not a replacement for Symbol Layer in every workflow

The current implementation already includes:

- experimental labeling
- timeout control
- fast-typing protection control
- dynamic activation hint describing key count and timeout

See:

- [AutoShiftCollectionView.swift](Sources/KeyPathAppKit/UI/AutoShiftCollectionView.swift)
- [RulesSummaryView.swift](Sources/KeyPathAppKit/UI/RulesSummaryView.swift)

What is still generic rather than collection-specific:

- conflict dialog copy
- exclusivity recommendation messaging

The current runtime only has generic conflict detection and does not yet support first-class per-collection exclusivity metadata.

## Merge Decision

`Auto Shift Symbols` is acceptable as an experimental collection because:

- it solves a clear problem
- it is narrower than Symbol Layer and not just a clone
- its claimed key surface is limited and explicit
- most overlaps are either nonexistent or blocked by generic conflict detection
- the riskiest broadening options were intentionally deferred

It should remain experimental until:

- conflict copy is specialized where needed
- any future broader scopes are reviewed separately
