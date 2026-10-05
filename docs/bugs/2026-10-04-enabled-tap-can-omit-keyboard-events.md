# An enabled session tap can omit keyboard events

The isolated c6 guest experiment reached runtime readiness with its exact worker registered for flagsChanged (4096), while the requested mask was keyDown, keyUp, and flagsChanged (7168). The one root-context registration query occurred before target launch or hardware input. Enabled state alone therefore cannot establish that keyboard events are registered. This finding is specific to that observed worker; it does not prove that Input Monitoring is universally required.

The experimental build now records one worker-self registration query after enabling the tap, selecting only its own session/default tap rows. It distinguishes absence, multiple matches, API error, capacity overflow, and unexpected native ABI. Raw Accessibility and ListenEvent facts come through PermissionOracle; PostEvent reuses the worker's existing session capability snapshot. These are pre-tap startup facts, not simultaneous measurements. No permission requirements or readiness policy change in this diagnostic.

CGGetEventTapList resets global tap latency extrema. The query limits entries to 128 but has no wall-time timeout. Reports omit other processes, event contents, and latency values. Older strict physical collectors require a separately reviewed schema update before using this report.

Validation: actual report and verbatim native ABI/query/classifier compiled and pure interpretation/strict decoding checks passed without executing permission or tap APIs. The complete experimental KeyPath product compiled using explicit Xcode 27 because pinned Xcode 26.6 is absent. Verified prebuilt Metal bytes were reused temporarily; the build plugin was restored byte for byte. Five scoped Swift tests were authored; the full test target was not run. Signed guest validation and worker-self versus root-context comparison remain pending.

Next: compare both observers for the same worker, then implement truthful mask readiness and test permission/launch differences separately.
