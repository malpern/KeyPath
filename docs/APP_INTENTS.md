# App Intents (Siri & Shortcuts)

KeyPath exposes its core functionality via the App Intents framework, making it available to Siri, Shortcuts, Spotlight, and Apple Intelligence.

## Available Intents

### Get Current Layer

Returns the currently active keyboard layer as a string.

**Siri:** "What layer am I on in KeyPath?"

**Shortcuts:** Use the "Get Current Layer" action — returns a string you can use in conditions or display.

### Control Service

Start, stop, or restart the KeyPath keyboard remapping service.

**Siri:** "Start KeyPath" / "Stop KeyPath" / "Restart KeyPath"

**Shortcuts:** Use the "Control KeyPath Service" action and pick Start, Stop, or Restart.

### Send Action

Send any `keypath://` action URI. This exposes the full [Action URI System](ACTION_URI_SYSTEM.md) to Shortcuts.

**Shortcuts:** Use the "Send KeyPath Action" action with a URI like `keypath://launch/Obsidian`.

Examples:
- `keypath://launch/Terminal` — launch an app
- `keypath://system/mission-control` — trigger Mission Control
- `keypath://window/left` — snap window to left half
- `keypath://notify?title=Hello&body=World` — show a notification
- `keypath://script/~/scripts/my-script.sh` — run a script

## Shortcuts Recipes

### Toggle keyboard service on schedule

Create a Shortcut with a Time of Day automation:
1. At 9 AM → "Control KeyPath Service" → Start
2. At 6 PM → "Control KeyPath Service" → Stop

### Layer-conditional automation

Use "Get Current Layer" with an If action:
1. Get Current Layer
2. If result is "work" → open your work apps
3. Otherwise → do nothing

### Quick action from menu bar

Add any KeyPath Shortcut to your menu bar for one-click access:
1. Create a Shortcut with "Send KeyPath Action"
2. Set the URI (e.g., `keypath://system/mission-control`)
3. Pin the Shortcut to your menu bar

## Layer Entity

Layers are exposed as App Entities, which means Shortcuts can enumerate available layers dynamically. The layer list is fetched from the running Kanata instance via TCP — if the service is stopped, the query will fail gracefully.

## Implementation

App Intents are defined in `Sources/KeyPathAppKit/Intents/`:

| File | Purpose |
|------|---------|
| `GetCurrentLayerIntent.swift` | Query the current active layer |
| `ServiceControlIntent.swift` | Start/stop/restart the service |
| `SendActionIntent.swift` | Dispatch any `keypath://` action URI |
| `LayerEntity.swift` | App Entity for layers with dynamic query |
| `KeyPathShortcuts.swift` | `AppShortcutsProvider` — registers Siri phrases |

All intents delegate to existing infrastructure:
- `DistributedNotificationBridge.currentLayer` for current layer state
- `ActionDispatcher.shared` for action dispatch
- `RuntimeCoordinator` (via `AppDelegate`) for service lifecycle
- `ConfigFacade` for TCP layer queries
