--- === KeyPath ===
---
--- React to KeyPath keyboard layer changes and service state in Hammerspoon.
--- Uses macOS Distributed Notifications — no sockets, no polling.
---
--- Usage:
---   hs.loadSpoon("KeyPath")
---   spoon.KeyPath:onLayerChange(function(layer, previous)
---       if layer == "nav" then
---           -- show navigation overlay
---       end
---   end):start()
---
--- [KeyPath](https://github.com/malpern/KeyPath)

local obj = {}
obj.__index = obj

obj.name = "KeyPath"
obj.version = "1.0"
obj.author = "Micah Alpern <malpern@gmail.com>"
obj.license = "MIT - https://opensource.org/licenses/MIT"
obj.homepage = "https://github.com/malpern/KeyPath"

obj._watchers = {}
obj._layerCallbacks = {}
obj._serviceCallbacks = {}

--- KeyPath.currentLayer
--- Variable
--- The most recently reported layer name. Nil until the first layer change is received.
obj.currentLayer = nil

--- KeyPath.serviceState
--- Variable
--- The most recently reported service state ("running" or "stopped"). Nil until first report.
obj.serviceState = nil

--- KeyPath:onLayerChange(fn)
--- Method
--- Register a callback for layer change events.
---
--- Parameters:
---  * fn - A function that receives (layerName, previousLayerName)
---
--- Returns:
---  * The KeyPath object (for chaining)
function obj:onLayerChange(fn)
    self._layerCallbacks[#self._layerCallbacks + 1] = fn
    return self
end

--- KeyPath:onServiceState(fn)
--- Method
--- Register a callback for service state changes.
---
--- Parameters:
---  * fn - A function that receives (state) where state is "running" or "stopped"
---
--- Returns:
---  * The KeyPath object (for chaining)
function obj:onServiceState(fn)
    self._serviceCallbacks[#self._serviceCallbacks + 1] = fn
    return self
end

--- KeyPath:start()
--- Method
--- Start listening for KeyPath events via macOS Distributed Notifications.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The KeyPath object
function obj:start()
    self._watchers.layer = hs.distributednotifications.new(
        function(name, object, userInfo)
            if not userInfo then return end
            local layer = userInfo.layer
            local previous = userInfo.previous
            if not layer then return end

            self.currentLayer = layer

            for _, fn in ipairs(self._layerCallbacks) do
                fn(layer, previous)
            end
        end, "com.keypath.layerChanged"
    ):start()

    self._watchers.service = hs.distributednotifications.new(
        function(name, object, userInfo)
            if not userInfo then return end
            local state = userInfo.state
            if not state then return end

            self.serviceState = state

            for _, fn in ipairs(self._serviceCallbacks) do
                fn(state)
            end
        end, "com.keypath.serviceStateChanged"
    ):start()

    return self
end

--- KeyPath:stop()
--- Method
--- Stop listening for KeyPath events.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The KeyPath object
function obj:stop()
    for _, w in pairs(self._watchers) do
        w:stop()
    end
    self._watchers = {}
    return self
end

--- KeyPath:sendAction(uri)
--- Method
--- Send a keypath:// action URI to KeyPath.
---
--- Parameters:
---  * uri - A keypath:// URI string (e.g., "keypath://launch/Obsidian")
---
--- Returns:
---  * None
function obj:sendAction(uri)
    if not uri:match("^keypath://") then
        uri = "keypath://" .. uri
    end
    hs.urlevent.openURL(uri)
end

return obj
