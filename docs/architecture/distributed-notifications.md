# Distributed Notifications

KeyPath broadcasts state changes via macOS Distributed Notifications (`NSDistributedNotificationCenter`), allowing any process on the system to react to keyboard events without sockets, polling, or configuration.

## Why Distributed Notifications?

| Transport | Pros | Cons |
|-----------|------|------|
| TCP socket | Cross-platform, structured | Requires port discovery, reconnection logic |
| **Distributed Notifications** | **Zero-config, any process can listen** | macOS-only, fire-and-forget |
| URL scheme | Works from everything | Inbound only (to KeyPath) |

KeyPath uses Distributed Notifications for outbound events (KeyPath to the world) and the `keypath://` URL scheme for inbound commands (world to KeyPath). See [ACTION_URI_SYSTEM.md](ACTION_URI_SYSTEM.md) for the inbound side.

## Events

### `com.keypath.layerChanged`

Posted when the active keyboard layer changes. Deduplicated — repeated notifications for the same layer are suppressed.

| Field | Type | Description |
|-------|------|-------------|
| `layer` | String | The new active layer name (e.g., `"nav"`, `"base"`) |
| `previous` | String | The layer that was active before this change |

Sources: Kanata TCP `LayerChange` events and `push-msg` layer action URIs.

### `com.keypath.serviceStateChanged`

Posted when the Kanata service starts or stops successfully.

| Field | Type | Description |
|-------|------|-------------|
| `state` | String | `"running"` or `"stopped"` |

## Listening from Different Tools

### Hammerspoon

Use the [KeyPath.spoon](../Integrations/KeyPath.spoon/) for a clean API, or listen directly:

```lua
hs.distributednotifications.new(function(name, object, userInfo)
    print("Layer: " .. userInfo.layer .. " (was " .. userInfo.previous .. ")")
end, "com.keypath.layerChanged"):start()
```

### Swift

```swift
DistributedNotificationCenter.default().addObserver(
    forName: NSNotification.Name("com.keypath.layerChanged"),
    object: "com.keypath.app",
    suspensionBehavior: .deliverImmediately
) { notification in
    let layer = notification.userInfo?["layer"] as? String
    let previous = notification.userInfo?["previous"] as? String
    print("Layer changed: \(previous ?? "?") -> \(layer ?? "?")")
}
```

### Terminal (for debugging)

The system does not include a built-in CLI listener, but you can observe notifications using Hammerspoon's console or by writing a small Swift script. To verify notifications are being posted, check the KeyPath debug log:

```bash
tail -f ~/Library/Logs/KeyPath/keypath-debug.log | grep "Layer change"
```

### Keyboard Maestro

Keyboard Maestro can trigger macros from Distributed Notifications. Create a macro with the trigger "Distributed Notification Received" and set the notification name to `com.keypath.layerChanged`.

### Shortcuts / Siri / Apple Intelligence

KeyPath exposes [App Intents](APP_INTENTS.md) for direct Shortcuts and Siri integration — query the current layer, control the service, or send any action URI. For event-driven automation (reacting to layer changes), bridge via Hammerspoon:

```lua
spoon.KeyPath:onLayerChange(function(layer)
    if layer == "media" then
        hs.shortcuts.run("My Media Shortcut")
    end
end)
```

## Implementation

The bridge is implemented in `DistributedNotificationBridge.swift`. It observes the internal `NotificationCenter` event `.kanataLayerChanged` (which consolidates both TCP and push-msg sources) and rebroadcasts via `DistributedNotificationCenter`.

Key details:
- `deliverImmediately: true` — bypasses macOS notification coalescing so rapid hold-release layer switches are not missed
- Previous layer is tracked internally and included in every notification
- Duplicate layer names are suppressed (no notification if layer hasn't actually changed)
- Started once during `applicationDidFinishLaunching` via `AppNotificationWiring`

## Privacy

Only layer names and service state are broadcast. Keystrokes, key input events, and HRM trace data are never sent over Distributed Notifications.
