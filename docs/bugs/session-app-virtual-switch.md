# App-specific virtual switches in the session profile

The app generator writes `(defvirtualkeys vk_test XX)` and aliases such as
`(switch ((input virtual vk_test)) b break () a break)`. Kanata parsed this
correctly, but the session action whitelist rejected every `Action::Switch`.

The profile now accepts only empty fallback conditions and single active
virtual-input predicates referring to declared virtual keys. Every branch is
validated recursively, including nested switches, and all virtual-key action
rows are validated too. Callback/init functions and other predicates remain
unavailable. Device filtering, media output and Unicode output remain rejected.
A virtual-key index is not a physical OsCode and cannot qualify for unchanged
physical-input passthrough when those integer values happen to coincide.

`ActOnFakeKey` uses Kanata's TCP handler to enqueue layout row-1 press/release
and wake the processing channel. `XX` stores a `NoOpInput` coordinate without
emitting output. The switch evaluates that active coordinate and executes its
chosen branch in keyberon. It does not need the macOS DriverKit input event loop.

The real passthrough-engine test sends TCP Press and Release, verifies fallback
`a`, held-context `b`, and restored fallback `a`, each with down/up output, and
verifies that the virtual `XX` events emit nothing. Eligibility tests reject
nested media/Unicode branches and unsupported virtual-key definitions.

The Swift lifecycle starts AppContextService after tap and TCP readiness, then
signals the current frontmost app; activation releases the previous virtual key
before pressing the new one. Startup therefore uses the fallback until that
signal arrives. These Rust tests do not replace signed app / physical event-tap
acceptance testing.
