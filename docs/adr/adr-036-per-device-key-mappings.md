# ADR-036: Per-Device Key Mappings via Conditional Switch Wrapping

## Status
Accepted

## Context

KeyPath users with multiple keyboards (e.g., built-in laptop + external mechanical) want different key mappings per device. Kanata now supports `(device N)` switch conditions (PR #1974), enabling per-device behavior without duplicating entire layers.

macOS multi-device support is blocked upstream (psych3r/driverkit#15) — the device index is always 0. However, we can build and test the KeyPath data model and config generation now. Generated configs degrade gracefully: the `() <default> break` fallthrough catches all events when `device_index` is always 0.

## Decision

Use **per-key conditional switch wrapping**: only keys with different mappings across devices get `(switch ...)` blocks. All other keys emit normally, keeping configs readable and minimal.

### Data Model

Add `DeviceKeyOverride` struct and optional `deviceOverrides` on `KeyMapping`:

```swift
public struct DeviceKeyOverride: Codable, Equatable, Sendable {
    public let deviceHash: String   // From kanata --list, e.g. "0x1234ABCD"
    public let output: String       // Replaces the default output for this device
    public let behavior: MappingBehavior?  // Optional behavior override
}

// On KeyMapping:
public let deviceOverrides: [DeviceKeyOverride]?
```

### Config Generation

When a key has `deviceOverrides`, wrap it in a switch expression:

```
(switch
    ((device 0)) alternate-output break
    ((device 2)) another-output break
    () default-output break)
```

Key rules:
- **No overrides** → emit normally (no switch wrapper)
- **Has overrides** → wrap in switch, alias as `dev_<layer>_<key>`
- **Always include** `() <default> break` as final case
- **Unresolvable device hashes** (device not connected) → skip that case silently
- Device hash → index resolution uses `DeviceSelectionCache.shared.getConnectedDevices()`

## Consequences

- Backward-compatible: existing configs without `deviceOverrides` generate identically
- Config output is minimal — only affected keys get switch blocks
- When macOS multi-device support lands upstream, configs will "just work"
- UI for per-device editing is deferred to a follow-up PR
