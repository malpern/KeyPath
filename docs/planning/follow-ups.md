# Follow-up Work

## Add script output type to overlay mapper

The overlay mapper supports Keystroke, Launch App, Open URL, System Action, and Go to Layer as output types. Scripts are only available through Quick Launcher's editor.

**What:** Add a "Run Script" output type to the mapper's output type dropdown, with a file picker for the script path. Same permission flow as Quick Launcher — triggers the script permission confirmation dialog if scripts aren't enabled.

**Why:** Users should be able to assign a script to any key from the mapper, not just through Quick Launcher. Consistent with the principle that Quick Launcher is one surface for a capability, not the only surface.

**Depends on:** Script permission confirmation dialog (in progress).
