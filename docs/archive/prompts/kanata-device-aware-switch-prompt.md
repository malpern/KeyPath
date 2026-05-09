# Prompt: Device-Aware `switch` Conditions for Kanata

## Objective

Add a `device` condition to Kanata's `switch` action so that config authors can apply different layers/actions based on which physical keyboard originated a keypress. This enables Karabiner-Elements-style per-device rules within a single Kanata process.

**Upstream issue:** [jtroo/kanata#1777](https://github.com/jtroo/kanata/issues/1777) — labelled "PRs welcome"

---

## Motivation

Users with multiple keyboards (e.g., laptop built-in + external mechanical) want different mappings per device. Today, Kanata can only include/exclude entire devices at startup via `macos-dev-names-include` / `linux-dev-names-include` in `defcfg`. There is no way to route events differently at runtime based on which device they came from. The workaround — running multiple Kanata instances — is fragile and unsupported.

Karabiner-Elements solves this with `device_if` / `device_unless` conditions in its complex modifications JSON, matching on `vendor_id`, `product_id`, `device_address`, and `is_built_in_keyboard`. We want similar expressiveness in Kanata's `switch` action.

---

## Current Architecture (What Exists Today)

### Device Enumeration

Kanata already enumerates devices at startup:

**macOS** (`src/oskbd/macos.rs`): Uses `karabiner_driverkit::fetch_devices()` which returns a list with `hash` (u64), `vendor_id`, `product_id`, and `product_key` (name string). Devices are filtered by `macos-dev-names-include/exclude` before input is seized.

**Linux** (`src/oskbd/linux.rs`): Uses `discover_devices()` which returns `Vec<(Device, String)>` — evdev `Device` objects with `.name()`, `.physical_path()`, and USB IDs via `device.input_id()`. The `KbdIn` struct stores a `HashMap<Token, (Device, String)>` mapping poll tokens to devices.

### Event Pipeline (The Gap)

Once devices are registered, **device identity is discarded** in the event stream:

- **macOS**: `KbdIn::read()` calls `wait_key(&mut DKEvent)` which returns `{value, page, code}` — no device identifier. The DriverKit layer merges all grabbed devices into a single event pipe.

- **Linux**: `KbdIn::read()` iterates `self.events` (from `poll()`), knows which `Token` each event comes from (and therefore which device), but returns `Vec<InputEvent>` without device metadata.

- **KeyEvent struct** (`src/oskbd/mod.rs`):
  ```rust
  pub struct KeyEvent {
      pub code: OsCode,
      pub value: KeyValue,  // Press, Release, Repeat, Tap, WakeUp
  }
  ```
  No device field.

- **handle_input_event** (`src/kanata/mod.rs`): Converts `KeyEvent` to keyberon `Event::Press(0, keycode)` with hardcoded `row = 0`. Device identity is permanently lost here.

### Switch Action (Where Device Conditions Would Go)

**Parser** (`parser/src/cfg/switch.rs`): Parses `(switch ...)` with triples of `<condition> <action> <break|fallthrough>`. Conditions can be:
- Key name atoms (e.g., `a`, `lctrl`) — active key check
- `(or ...)` / `(and ...)` / `(not ...)` — boolean combinators
- `(layer layer-name)` — active layer check
- `(base-layer layer-name)` — default layer check
- `(input real|virtual key)` — coordinate check
- `(key-history key N)` — Nth recent key
- `(key-timing N lt|gt ms)` — timing check

**OpCode system** (`keyberon/src/action/switch.rs`): Conditions are compiled to `OpCode` (u16 discriminant + payload). Runtime evaluates via `evaluate_boolean()` which takes iterators of active keys, positions, layers, and history.

**Runtime evaluation** (`keyberon/src/layout.rs`, line 2242): `Switch` cases are evaluated in `Layout::process_action()`. The evaluation context includes:
- `active_keys`: Iterator of currently pressed `KeyCode`s
- `active_positions`: Iterator of active `KCoord` (row, column)
- `historical_keys` / `historical_positions`: Recent key/coord history
- `layers`: Currently active layer indices
- `default_layer`: Base layer index

**There is no device information in the evaluation context.**

---

## Proposed Design

### 1. Carry Device Identity Through the Event Pipeline

**Add a device index to events.** Each grabbed device gets a stable `u8` index (0–255, assigned at registration). This index travels with every event from OS read through to switch evaluation.

#### a. Extend `KeyEvent`

```rust
// src/oskbd/mod.rs
pub struct KeyEvent {
    pub code: OsCode,
    pub value: KeyValue,
    pub device_index: u8,  // NEW: index into registered device table
}
```

#### b. Populate on macOS

The DriverKit `wait_key` C function currently returns `{value, page, code}`. The DriverKit layer would need to also return a device identifier. **If modifying the C bridge is out of scope**, an alternative is:
- If only one device is registered, `device_index = 0` always.
- If multiple devices: the DriverKit layer already knows which IOHIDDevice the event came from — expose it.
- **Fallback**: use `device_index = 0` (unknown) and let `(device ...)` conditions simply not match. This is safe because macOS users can still use the existing `macos-dev-names-include/exclude` for device filtering.

#### c. Populate on Linux

Linux is straightforward. `KbdIn::read()` already knows the `Token` → device mapping. When iterating `self.events`:

```rust
// src/oskbd/linux.rs, in read()
for event in &self.events {
    let token = event.token();
    let device_index = self.token_to_index[&token]; // NEW lookup
    // ... create InputEvent with device_index ...
}
```

#### d. Thread through kanata core

In `handle_input_event` (`src/kanata/mod.rs`), use `device_index` as the row in keyberon events:

```rust
// Instead of hardcoded row = 0:
let row = event.device_index;
let kbrn_ev = Event::Press(row, evc);
```

This repurposes the existing `row` field (currently always 0) as the device discriminator, avoiding changes to the keyberon `Event` type.

### 2. Device Registry

**New struct** to store metadata for registered devices:

```rust
// src/kanata/mod.rs or new file src/kanata/device_registry.rs
pub struct DeviceInfo {
    pub index: u8,
    pub name: String,       // product_key / evdev name
    pub vendor_id: u16,
    pub product_id: u16,
    pub hash: u64,          // macOS device hash (0 on Linux)
}

pub struct DeviceRegistry {
    devices: Vec<DeviceInfo>,       // indexed by device_index
    name_to_index: HashMap<String, u8>,
}
```

Populated during `KbdIn::new()` on both platforms.

### 3. New Switch Condition: `(device ...)`

#### Config Syntax

```lisp
;; Match by device name (substring match, case-insensitive)
(switch
  ((device "Kinesis Advantage360") a (layer kinesis-base) break)
  ((device "Apple Internal") a (layer laptop-base) break)
)

;; Match by device index (for positional matching)
(switch
  ((device 0) a layer1 break)
  ((device 1) a layer2 break)
)

;; Combine with other conditions using boolean operators
(switch
  ((and (device "Kinesis") (layer nav)) a some-action break)
)
```

#### Parser Changes (`parser/src/cfg/switch.rs`)

Add `"device"` to the match in `parse_switch_case_bool()`:

```rust
"device" => {
    // Accept string (name match) or number (index match)
    let arg = sexpr_iter.next().ok_or("device requires an argument")?;
    match arg {
        SExpr::Atom(name) => {
            if let Ok(idx) = name.parse::<u8>() {
                OpCode::new_device_index(idx)
            } else {
                // Store name in string interner, emit OpCode with interned ID
                OpCode::new_device_name(interner.intern(name))
            }
        }
        _ => bail!("device argument must be a string or number"),
    }
}
```

#### OpCode Extension (`keyberon/src/action/switch.rs`)

Add new OpCode variants:

```rust
const DEVICE_INDEX_VAL: u16 = 855;
const DEVICE_NAME_VAL: u16 = 856;

// In OpCodeType:
DeviceIndex(u8),
DeviceName(u16),  // interned string ID
```

#### Runtime Evaluation

Extend `evaluate_boolean()` signature to accept current device index:

```rust
fn evaluate_boolean(
    bool_expr: &[OpCode],
    key_codes: impl Iterator<Item = KeyCode> + Clone,
    inputs: impl Iterator<Item = KCoord> + Clone,
    // ... existing params ...
    current_device: u8,           // NEW
    device_registry: &DeviceRegistry, // NEW
) -> bool
```

In the match:
```rust
OpCodeType::DeviceIndex(idx) => current_device == idx,
OpCodeType::DeviceName(name_id) => {
    let name = interner.resolve(name_id);
    device_registry.get(current_device)
        .map(|d| d.name.to_lowercase().contains(&name.to_lowercase()))
        .unwrap_or(false)
}
```

### 4. Pass Device Context to Layout

The keyberon `Event::Press(row, col)` already carries `row`. If we repurpose row as device_index, then in `Layout::process_action()` where `Switch` is evaluated, we have access to the originating device via the event's row/coord.

In `layout.rs` line 2242, when evaluating switch:
```rust
Switch(sw) => {
    let current_device = coord.0; // row = device_index
    // Pass current_device to sw.actions(...)
}
```

---

## Scope Boundaries

### In Scope (This PR)
- Device index on `KeyEvent` (macOS + Linux)
- `DeviceRegistry` populated at startup
- `(device "name")` and `(device N)` conditions in `switch`
- Parser, OpCode, and runtime evaluation changes
- Tests: parser tests with device conditions, runtime tests with mock device events
- Documentation in `docs/config.adoc`

### Out of Scope (Future Work)
- Windows support (can default to `device_index = 0`)
- macOS DriverKit C bridge changes (use fallback if needed)
- `(device-vendor-id N)` / `(device-product-id N)` conditions (can add later)
- Device hot-plug notifications at runtime
- `defdevice` config block for naming/aliasing devices

---

## Karabiner-Elements Reference

For comparison, Karabiner's device conditions look like:

```json
{
  "type": "device_if",
  "identifiers": [
    { "vendor_id": 1452, "product_id": 8199, "is_keyboard": true }
  ]
}
```

Properties available: `vendor_id`, `product_id`, `device_address` (Bluetooth MAC), `location_id` (USB port), `is_built_in_keyboard`, `is_keyboard`, `is_pointing_device`, `manufacturer`, `product`, `serial_number`, `transport`.

Multiple identifiers use OR logic; properties within one identifier use AND logic.

Kanata's `(device ...)` is intentionally simpler (name substring or index) for the initial implementation, with room to expand.

---

## Test Plan

1. **Parser tests** (`parser/src/cfg/switch.rs` tests):
   - `(device "Keyboard Name")` parses to correct OpCode
   - `(device 0)` parses to DeviceIndex OpCode
   - `(and (device "foo") a)` composes with boolean operators
   - Invalid args produce clear errors

2. **Runtime tests** (`keyberon/src/action/switch.rs` tests):
   - DeviceIndex condition matches correct device
   - DeviceName condition does case-insensitive substring match
   - Non-matching device falls through to next case
   - Device condition works with and/or/not combinators

3. **Integration tests**:
   - Linux: multi-device event routing with different device indices
   - Config with device-specific layers loads and switches correctly

---

## Key Files to Modify

| File | Change |
|------|--------|
| `src/oskbd/mod.rs` | Add `device_index` to `KeyEvent` |
| `src/oskbd/linux.rs` | Populate `device_index` from token→index map in `read()` |
| `src/oskbd/macos.rs` | Populate `device_index` (0 if single device, or from DriverKit) |
| `src/kanata/mod.rs` | Use `device_index` as row in `handle_input_event()`; store `DeviceRegistry` |
| `parser/src/cfg/switch.rs` | Parse `(device ...)` condition |
| `keyberon/src/action/switch.rs` | Add DeviceIndex/DeviceName OpCode variants; extend `evaluate_boolean()` |
| `keyberon/src/layout.rs` | Pass device context when evaluating Switch action |
| `docs/config.adoc` | Document `(device ...)` condition syntax and examples |

---

## Style Notes

- Kanata uses `log::info!` / `log::warn!` / `log::trace!` for logging
- Parser errors use `anyhow::bail!` and `anyhow::Result`
- Config options use list-style `(name value)`, not colon-style `:name value`
- Tests are in `#[cfg(test)] mod tests` blocks within each file
- PR should include a `CHANGELOG.md` entry under `[Unreleased]`
