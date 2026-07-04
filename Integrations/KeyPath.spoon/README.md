# KeyPath.spoon

A [Hammerspoon](https://www.hammerspoon.org/) Spoon that lets you react to KeyPath keyboard layer changes and service state. Uses macOS Distributed Notifications — no sockets, no polling, no configuration.

## Install

Copy `KeyPath.spoon` to your Spoons directory:

```bash
cp -r Integrations/KeyPath.spoon ~/.hammerspoon/Spoons/
```

Or symlink it for development:

```bash
ln -s "$(pwd)/Integrations/KeyPath.spoon" ~/.hammerspoon/Spoons/KeyPath.spoon
```

Then reload Hammerspoon (`Cmd+Shift+R` or `hs.reload()`).

## Quick Start

Add to your `~/.hammerspoon/init.lua`:

```lua
hs.loadSpoon("KeyPath")

spoon.KeyPath:onLayerChange(function(layer, previous)
    print("Layer: " .. layer .. " (was " .. previous .. ")")
end):start()
```

## API

### `spoon.KeyPath:onLayerChange(fn)`

Register a callback for layer changes. `fn` receives `(layerName, previousLayerName)`. Returns `self` for chaining.

### `spoon.KeyPath:onServiceState(fn)`

Register a callback for service start/stop. `fn` receives `(state)` where state is `"running"` or `"stopped"`. Returns `self` for chaining.

### `spoon.KeyPath:start()`

Start listening for KeyPath events. Returns `self`.

### `spoon.KeyPath:stop()`

Stop listening. Returns `self`.

### `spoon.KeyPath:sendAction(uri)`

Send a `keypath://` action URI to KeyPath. Accepts full URIs or shorthand (auto-prefixes `keypath://`).

```lua
spoon.KeyPath:sendAction("launch/Obsidian")
spoon.KeyPath:sendAction("keypath://notify?title=Hello")
```

### `spoon.KeyPath.currentLayer`

The most recently reported layer name. `nil` until the first layer change.

### `spoon.KeyPath.serviceState`

The most recently reported service state. `nil` until first report.

## Examples

### Show a notification on layer change

```lua
hs.loadSpoon("KeyPath")

spoon.KeyPath:onLayerChange(function(layer, previous)
    if layer ~= "base" then
        hs.notify.show("KeyPath", "", "Layer: " .. layer)
    end
end):start()
```

### Layer-aware window management

```lua
hs.loadSpoon("KeyPath")

spoon.KeyPath:onLayerChange(function(layer)
    if layer == "window" then
        -- Show a window grid overlay
        hs.grid.show()
    end
end):start()
```

### Route URLs based on active layer

Combine with [ProfileRouter.spoon](https://github.com/malpern/ProfileRouter):

```lua
hs.loadSpoon("KeyPath")
hs.loadSpoon("ProfileRouter")

-- When in "work" layer, cycle to work profile
spoon.KeyPath:onLayerChange(function(layer)
    if layer == "work" then
        -- Your work-layer automation here
    end
end):start()

spoon.ProfileRouter:start()
```

### Send KeyPath actions from Hammerspoon hotkeys

```lua
hs.loadSpoon("KeyPath")

-- Ctrl+Shift+M → launch Mission Control via KeyPath
hs.hotkey.bind({"ctrl", "shift"}, "m", function()
    spoon.KeyPath:sendAction("system/mission-control")
end)

spoon.KeyPath:start()
```

## Requirements

- [Hammerspoon](https://www.hammerspoon.org/) 0.9.93+
- [KeyPath](https://github.com/malpern/KeyPath) with distributed notification support

## How It Works

KeyPath broadcasts layer changes and service state via macOS Distributed Notifications (`NSDistributedNotificationCenter`). This Spoon subscribes to those notifications using `hs.distributednotifications`. No network connections or configuration needed — if KeyPath is running, events flow automatically.

See [Distributed Notifications](../../docs/architecture/distributed-notifications.md) for the full protocol reference.
