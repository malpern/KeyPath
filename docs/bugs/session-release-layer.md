# Layer cancellation in the session profile

Generated navigation cancellation emits
`(multi (release-layer nav) XX (push-msg "layer:base"))`. Kanata parses its
release as `Action::ReleaseState(ReleasableState::Layer(index))`, which the
session whitelist previously rejected.

Keyberon handles this by removing matching `LayerModifier` states. It retains
normal held key states, including their original output and physical coordinate;
subsequent physical releases therefore release the output selected when the key
was pressed. No platform input or output operation is performed by layer release.

The profile now admits only the layer variant. Every surrounding `multi`/switch
branch is still recursively checked. `release-key`, media and Unicode output
remain unavailable.

The real passthrough-engine regression enters nav with a held Control modifier,
holds a nav-mapped `b → d`, cancels nav, and verifies a new `c` uses base. The
held `d` and Control remain until their original physical owners release them;
the test verifies exact up events and an empty final held-key state. Explicit
engine ticks provide deterministic timing without the macOS DriverKit input
loop. Signed physical event-tap acceptance remains separate.
