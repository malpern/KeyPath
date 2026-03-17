# ADR-036: Per-Device Key Mappings via Conditional Switch Wrapping

**Status:** Accepted
**Date:** 2026-03-14

## Context

KeyPath users with multiple keyboards (e.g., a split ergo board for typing and a macropad for shortcuts) want to assign different key mappings per device. Pressing the same physical key on different keyboards should trigger different actions.

Kanata now supports a `(device N)` switch condition ([jtroo/kanata#1974](https://github.com/jtroo/kanata/pull/1974)) that matches against the originating device's index. This gives us a config-level primitive for per-device behavior. The question is how KeyPath should generate configs that use it.

Three approaches were considered:

1. **Always wrap every key** in `(switch ((device N)) ... break)` blocks, even for single-keyboard users or keys with identical mappings across devices.
2. **Per-layer device configs** — generate entirely separate `deflayer` blocks per device.
3. **Per-key conditional wrapping** — only emit `(device N)` switch blocks for keys where the user has actually assigned different behavior per device.

## Decision

KeyPath uses **per-key conditional switch wrapping**. Device-scoped `(switch ...)` blocks are emitted only for individual keys that have different mappings across devices. All other keys are emitted as normal kanata config.

```
;; User assigns 'a' differently per device, but 'b' and 'c' are global:
(deflayer base
  (switch
    ((device 0)) x break
    ((device 1)) y break
    () a break)
  b c)
```

Rules:

- **No per-device rules on a key** → emit the key action directly, no switch wrapper.
- **Different behavior per device** → wrap in `(switch ((device N)) <action> break ...)`.
- **Always include a default fallthrough case** → `() <original-action> break` as the final case, so unassigned devices get the base mapping.

## Consequences

### Positive

- **Clean configs for single-keyboard users** — no unnecessary switch wrappers; configs look identical to non-device-aware configs.
- **Graceful degradation on macOS** — until macOS multi-device support lands ([psych3r/driverkit#15](https://github.com/psych3r/driverkit/pull/15)), all events have `device_index: 0`. The default fallthrough case catches everything, so configs work correctly on macOS today.
- **Readable and debuggable** — only keys with actual per-device behavior have switch blocks, making it easy to see what's device-specific at a glance.
- **Composable** — `(device N)` works with boolean operators: `(and (device 0) (layer nav))`, `(not (device 0))`, etc. KeyPath can generate increasingly sophisticated rules as needed.

### Negative

- **Per-key granularity adds config complexity** — a layer with many per-device overrides will have many inline switch blocks, which could get verbose. Acceptable for now; a future `(defdevice ...)` kanata feature would enable cleaner syntax.
- **Device indices are not yet stable** — indices are assigned by registration order, not hardware identity. A future kanata PR for stable hot-plug indexing will address this. For now, KeyPath should document that indices may change on replug/reboot.

## Dependency Chain

```
psych3r/driverkit#15          Add device_hash to DKEvent (macOS)
        |
        v
jtroo/kanata#1974             (device N) switch condition (merged foundation)
        |
        v
kanata macOS multi-device PR  Consume driverkit 0.3.0, map hash → index
        |
        v
KeyPath config generation     Emit (switch ((device N)) ...) per-key
```

KeyPath config generation can be built and tested now. Actual macOS device discrimination requires the upstream chain to land.

## Related

- [ADR-034](adr-034-kanata-engine-app-bundle-for-tcc-identity.md): KanataEngine.app bundle for TCC identity
- [ADR-035](adr-035-bundle-id-tcc-detection-with-path-fallback.md): Bundle ID TCC detection
- KeyPath issue: [#63](https://github.com/malpern/KeyPath/issues/63)
- kanata fork issues: [#6](https://github.com/malpern/kanata/issues/6) (defdevice), [#8](https://github.com/malpern/kanata/issues/8) (macOS multi-device), [#9](https://github.com/malpern/kanata/issues/9) (stable indexing)
