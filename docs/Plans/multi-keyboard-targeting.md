# Multi-Keyboard Targeting Plan

**Status:** Planned
**Created:** December 2024
**Last Updated:** December 2024

## Overview

Allow users to control which keyboards KeyPath modifies, using Kanata's native `macos-dev-names-include/exclude` feature.

## Problem Statement

Users with multiple keyboards often want to:
1. Exclude a gaming keyboard from remapping
2. Only remap an external keyboard, not the built-in
3. Have different configurations per device (future)

Karabiner Elements supports per-device and per-rule targeting. KeyPath currently applies all rules to all keyboards.

## Kanata's Native Capabilities

Kanata supports global device filtering in `defcfg`:

```lisp
(defcfg
  ;; Only intercept these keyboards (all rules apply to them)
  macos-dev-names-include (
    "Apple Internal Keyboard / Trackpad"
    "Corne Keyboard"
  )

  ;; OR exclude specific keyboards (all others are intercepted)
  macos-dev-names-exclude (
    "Logitech G Pro Gaming Keyboard"
  )
)
```

**Limitation:** This is global — all rules apply to all filtered devices. Kanata has no `device_if` equivalent for per-rule targeting.

## Scope

### Phase 1: Global Device Filter (This Plan)

**What users get:**
- Toggle which keyboards KeyPath controls
- All enabled rules apply to all enabled keyboards

**What we build:**
1. `KeyboardDeviceService` — enumerate keyboards via IOKit
2. `DeviceSettings` model — persist known devices + enabled state
3. "My Keyboards" UI — simple toggle list
4. Config generation — emit `macos-dev-names-include/exclude` in defcfg

**Single Kanata instance. No architectural changes.**

### Phase 2: Per-Device Rule Collections (Future)

Would require running multiple Kanata instances with separate configs. Significant complexity:
- N daemons, N TCP connections, N log streams
- Layer state synchronization across instances
- InstallerEngine/KanataManager refactoring

**Not in scope for Phase 1.**

## Capability Matrix

| Capability | Kanata Support | KeyPath Work Needed |
|------------|---------------|---------------------|
| Global device filter | ✅ Native | UI + config generation |
| Discover connected keyboards | ❌ | IOKit service |
| Remember disconnected devices | ❌ | Persistence layer |
| Per-rule device targeting | ❌ | Multi-instance (Phase 2) |

## Use Cases Covered

| Use Case | Phase 1 | Phase 2 |
|----------|---------|---------|
| "Ignore my gaming keyboard" | ✅ | ✅ |
| "Only remap external keyboard" | ✅ | ✅ |
| "Vim nav on external only" | ❌ | ✅ |
| "Different caps behavior per keyboard" | ❌ | ✅ |

## Design: "My Keyboards"

Apple-inspired design philosophy: Progressive disclosure, sensible defaults, one obvious path.

### UI Mockup

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  My Keyboards                                                   │
│                                                                 │
│  KeyPath applies your remappings to these keyboards.            │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  ┌──────┐                                                 │  │
│  │  │ ⌨️   │  Built-in Keyboard                        ●    │  │
│  │  └──────┘  Apple Internal Keyboard                        │  │
│  ├───────────────────────────────────────────────────────────┤  │
│  │  ┌──────┐                                                 │  │
│  │  │ ⌨️   │  Corne                                    ●    │  │
│  │  └──────┘  Split ergonomic keyboard                       │  │
│  ├───────────────────────────────────────────────────────────┤  │
│  │  ┌──────┐                                                 │  │
│  │  │ 🎮   │  Logitech G Pro                           ○    │  │
│  │  └──────┘  Gaming keyboard                                │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ○ = not modified   ● = modified                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Design Decisions

1. **No "All Devices" toggle** — show actual devices, let user toggle each
2. **Visual device icons** — keyboard vs gaming vs mouse
3. **Friendly names** — "Built-in Keyboard" not "Apple Internal Keyboard / Trackpad"
4. **Simple toggle** — on/off, not include/exclude mental model
5. **Remember disconnected devices** — show greyed out with "Not connected"
6. **All enabled by default** — users opt-out devices they don't want

### Empty State

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  My Keyboards                                                   │
│                                                                 │
│            ┌──────┐                                             │
│            │  ⌨️  │                                             │
│            └──────┘                                             │
│                                                                 │
│       No keyboards detected                                     │
│                                                                 │
│       Connect a keyboard to get started.                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Location in App

**Option A: Sidebar item** (recommended for discoverability)
```
┌─────────┬───────────────────────────────────┐
│ Rules   │                                   │
│ ─────── │                                   │
│ Vim     │                                   │
│ Hyper   │         [content area]            │
│         │                                   │
│ ─────── │                                   │
│ ⌨️ My   │                                   │
│ Keyboards                                   │
│         │                                   │
│ ⚙️ Settings                                 │
└─────────┴───────────────────────────────────┘
```

**Option B: Settings section** — simpler, less discoverable

## Data Model

```swift
// Stored in DeviceSettings.json
struct DeviceSettings: Codable {
    var knownDevices: [KnownDevice]
}

struct KnownDevice: Codable, Identifiable {
    let id: String              // Stable identifier (name + vendor/product if available)
    let displayName: String     // "Built-in Keyboard"
    let systemName: String      // "Apple Internal Keyboard / Trackpad"
    var isEnabled: Bool         // User's choice
    var lastSeen: Date          // For sorting/cleanup
}
```

## Implementation

### 1. KeyboardDeviceService

```swift
// Sources/KeyPathAppKit/Services/KeyboardDeviceService.swift
import IOKit

class KeyboardDeviceService {
    static let shared = KeyboardDeviceService()

    /// Enumerate currently connected keyboards via IOKit
    func discoverKeyboards() -> [KeyboardDevice] {
        // Use IOKit to enumerate HID keyboards
        // Filter by usage page (Generic Desktop) and usage (Keyboard)
    }

    /// Observe device connect/disconnect events
    func observeDeviceChanges() -> AsyncStream<[KeyboardDevice]> {
        // IOKit notifications for connect/disconnect
    }
}

struct KeyboardDevice: Identifiable {
    let id: String                      // Unique identifier
    let name: String                    // "Apple Internal Keyboard / Trackpad"
    let vendorID: Int?
    let productID: Int?
    let isBuiltIn: Bool                 // Heuristic: contains "Internal"
    let isConnected: Bool
}
```

### 2. Device Settings Persistence

```swift
// Sources/KeyPathAppKit/Services/DeviceSettingsStore.swift

class DeviceSettingsStore {
    private let fileURL: URL  // ~/Library/Application Support/KeyPath/DeviceSettings.json

    func load() async throws -> DeviceSettings
    func save(_ settings: DeviceSettings) async throws
}
```

### 3. Config Generation

```swift
// Addition to ConfigurationService.swift

func deviceFilterClause(_ settings: DeviceSettings) -> String? {
    let enabled = settings.knownDevices.filter { $0.isEnabled }
    let disabled = settings.knownDevices.filter { !$0.isEnabled }

    // If all enabled, no clause needed
    if disabled.isEmpty { return nil }

    // If all disabled, warn user (edge case)
    if enabled.isEmpty { return nil }

    // Use whichever list is shorter for cleaner config
    if enabled.count <= disabled.count {
        return """
        macos-dev-names-include (
            \(enabled.map { "\"\($0.systemName)\"" }.joined(separator: "\n    "))
        )
        """
    } else {
        return """
        macos-dev-names-exclude (
            \(disabled.map { "\"\($0.systemName)\"" }.joined(separator: "\n    "))
        )
        """
    }
}
```

### 4. SwiftUI View

```swift
// Sources/KeyPathAppKit/UI/MyKeyboardsView.swift

struct MyKeyboardsView: View {
    @StateObject private var viewModel = MyKeyboardsViewModel()

    var body: some View {
        List {
            Section {
                ForEach(viewModel.devices) { device in
                    KeyboardRow(device: device) {
                        viewModel.toggle(device)
                    }
                }
            } header: {
                Text("KeyPath applies your remappings to these keyboards.")
            }
        }
        .navigationTitle("My Keyboards")
    }
}

struct KeyboardRow: View {
    let device: KnownDevice
    let onToggle: () -> Void

    var body: some View {
        HStack {
            // Device icon
            Image(systemName: device.isBuiltIn ? "laptopcomputer" : "keyboard")
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading) {
                Text(device.displayName)
                    .font(.body)
                Text(device.systemName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: .constant(device.isEnabled))
                .labelsHidden()
                .onChange(of: device.isEnabled) { _ in onToggle() }
        }
        .opacity(device.isConnected ? 1.0 : 0.5)
    }
}
```

## Comparison with Karabiner Elements

| Karabiner | KeyPath (Proposed) |
|-----------|--------------------|
| Devices tab with checkboxes | "My Keyboards" with toggles |
| Per-rule JSON conditions (`device_if`) | Global device filter only |
| Shows vendor/product IDs | Friendly names only |
| Complex include/exclude logic | Simple on/off per device |
| Requires JSON for per-rule targeting | Not supported (clear limitation) |

## What We're NOT Building (Phase 1)

- Per-collection device targeting (requires multi-instance Kanata)
- Vendor/product ID display (unnecessary complexity)
- Device renaming (nice-to-have, not essential)
- Mouse support (Kanata limitation on macOS)

## Dependencies

- IOKit framework for device enumeration
- No new Kanata features required

## Estimated Effort

- KeyboardDeviceService: 1 day
- DeviceSettings persistence: 0.5 day
- Config generation changes: 0.5 day
- UI implementation: 1 day
- Testing: 1 day

**Total: ~4 days**

## Open Questions

1. How to generate stable device IDs when vendor/product IDs aren't available?
2. Should disconnected devices auto-remove after N days?
3. Should device changes require manual "Apply" or auto-save?

## References

- [Kanata config.adoc - macOS device filtering](https://github.com/jtroo/kanata/blob/main/docs/config.adoc)
- [Karabiner Elements device conditions](https://karabiner-elements.pqrs.org/docs/json/complex-modifications-manipulator-definition/conditions/device/)
- [Karabiner GUI feature request for per-rule device targeting](https://github.com/pqrs-org/Karabiner-Elements/issues/1073)
