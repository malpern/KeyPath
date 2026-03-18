# KeyPath Layout Tracer

`KeyPathLayoutTracer` is a separate macOS helper app for tracing physical keyboard geometry from a reference image and exporting a KeyPath-compatible native layout JSON.

## Launch

```bash
cd /Users/malpern/local-code/KeyPath-layout-tracer
swift run KeyPathLayoutTracer
```

Or:

```bash
/Users/malpern/local-code/KeyPath-layout-tracer/Scripts/run-layout-tracer.sh
```

## Current MVP

- open a keyboard image
- open an existing KeyPath native layout JSON
- add/select/delete keys
- drag keys
- resize keys from the bottom-right handle
- nudge selected keys with arrow buttons or keyboard move commands
- snap moved/resized keys to nearby key edges
- save back to the current layout JSON or save as a new KeyPath-compatible physical layout JSON

## Notes

- This tool focuses on geometry only.
- Labels and keycodes are placeholders by default but can be edited in the inspector.
- Exported JSON matches the native `PhysicalLayout` shape used by KeyPath built-in layouts.
