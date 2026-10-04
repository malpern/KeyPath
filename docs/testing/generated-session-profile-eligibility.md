# Generated profile eligibility (DL-11)

Source audit: 2026-10-03, base `234f7b87`. This is a bounded parser/test slice,
not physical or runtime acceptance. It does not change generation or select a
backend. Run the generated-profile tests against the freshly built bridge before
accepting the predicted results below.

## Actual profiles

`RuleCollectionCatalog.defaultCollections()` loads the bundled
`rule-collection-catalog.json`. Six collections are enabled in that catalog:

| Collection | Default generated behavior relevant to session eligibility |
| --- | --- |
| macOS Function Keys | Brightness and media consumer-key output, plus system push messages |
| Vim - Apple Keyboard Shortcuts | Space-activated navigation, modifier combinations, macros, fake-key notifications, one-shot layer cleanup |
| Caps Lock Remap | Physical Caps Lock taps and holds Hyper |
| Fast Navigation | Managed repeat configuration |
| Home Row Arrows | F-activated arrow layer |
| Quick Launcher | Hyper-activated launcher with push messages |

The other catalog entries ship disabled: Leader Key, Neovim Terminal, Mission
Control, Window Snapping, Backup Caps Lock, Escape, Delete Enhancement, Home Row
Mods, Home Row Layer Toggles, Chord Groups, Sequences, Numpad, Symbol, Function,
Auto Shift Symbols, and Home Row Navigation System.

The catalog profile is rejected: the media outputs and physical Caps remap each
independently exceed the current session contract. Reset is a different profile:
`RuntimeCoordinator` enables only macOS Function Keys, which still rejects.
An empty collection list, or a simple custom mapping without the function-key
collection ID, also receives enabled system media defaults and rejects.

`KanataConfiguration.generateFromCollections` supplies deterministic empty
inputs through its compatibility overload. Its actual service caller is
`ConfigurationService`, which captures `KanataGenerationInputs` before rendering.
There is no `RuleCollectionConfigurationService` type at this base.

## Exact validator input

Write the unchanged generated string to a temporary `.kbd`, verify it through
`KanataHostBridge.validateConfig`, then call `validateSessionConfig` with:

```swift
SessionKeyMap.keyCodeToUsage.values.filter { $0 != 57 }.sorted()
```

This matches both `SessionRuntimeWorker` and `ConfigReloadCoordinator`. Caps Lock
has a translation-map entry but usage 57 is intentionally excluded from capture
eligibility. Fn and consumer keys are not mapped at all. Do not substitute all
USB page-7 usages, include Caps Lock, or invent consumer usages to admit a profile.

The Rust validator uses Kanata's parsed action tree, not text matching. Supported
keyboard actions include remaps, modifier combinations, hold/tap, one-shot,
tap-dance, chords, forks and keyboard macros, subject to every nested action and
output being supported. Push messages, supported fake-key actions and listed
macro-delay/cancellation actions are allowed. Unlisted action variants reject.
For example, generated one-shot cleanup uses `release-layer`; do not infer that
all generated navigation variants are eligible from a hand-authored layer test.

Device selection and even a generated VirtualHID exclusion reject because a
session event stream cannot attribute its originating device. The empty-input
catalog test has no connected-device snapshot, so it does not by itself cover
that additional real-generation restriction.

## Proposed bounded support cutoff

Admit only the exact unchanged candidate that passes the canonical validator.
An explicitly selected standard function-key profile, with simple ordinary-key
remapping and no device filters, is the smallest meaningful generated positive
case. Merely declaring a candidate "default", "home row", or "navigation" is
insufficient. Caps remaps, media outputs, mouse, Unicode/text, device filters and
unimplemented parsed action variants remain outside this slice. Reject clearly;
never remove collection semantics or silently fall back to the driver backend.
A parser eligibility pass alone does not prove physical capture, injection,
protected-input behavior, layer notifications or lifecycle acceptance.

## Verification handoff

`GeneratedSessionProfileEligibilityTests` tests the actual catalog and reset,
implicit media-default insertion, explicit standard function keys, simple
remapping, isolated Caps remap, and generated VirtualHID exclusion. Every case
first requires ordinary Kanata validation to succeed; semantic rejections must
carry the advanced-backend reason rather than a parse error.

```sh
KEYPATH_SESSION_TEST_BRIDGE_PATH="$PWD/build/kanata-host-bridge/libkeypath_kanata_host_bridge.dylib" \
  swift test --filter GeneratedSessionProfileEligibilityTests
```

The explicit bridge path makes a missing library fail. Without an explicit path,
a missing worktree-local bridge skips; skipped tests are not acceptance evidence.
No installed-app library fallback is used. Builds and test execution are deferred
to the integrating root agent to avoid overlapping compilation.
