# macOS 27 renamed Accessibility; KeyPath still said "Accessibility"

**Date:** 2026-11-08
**Status:** Fixed

## Symptom

On macOS 27.3 the setup page's fallback button read "Add KeyPath to
Accessibility", but it opened a pane called "Device Control and Data Access".
Many other messages (recording, keyboard capture, the wizard's status rows,
diagnostics, errors, the About window) also said "Accessibility".

## Cause

macOS 27 renamed the pane. Its own string table
(`SecurityPrivacyExtension.appex`, key `ACCESSIBILITY`) now reads "Device Control
and Data Access". `LISTEN_EVENT` still reads "Input Monitoring". KeyPath already
had `AccessibilityPermissionPresentation`, which switches the name on macOS 27, but
about 45 user-facing strings bypassed it.

## Fix

Those strings now take the name from
`AccessibilityPermissionPresentation.current.name`. Not changed: TCC service names,
enum raw values, the canonical `"Accessibility"` keys that
`displayName(for:)` maps, VoiceOver labels, and kindaVim's own "Accessibility"
mode.

## Related: a switch that is on but does not count

On the Air, the switch for KeyPath was on and KeyPath still read as denied. The
`com.keypath.KeyPath` row in the system TCC database had a code requirement for
an **Apple Development** signed build, and the installed app is **Developer ID**
signed. LaunchServices knew 46 copies of KeyPath (Trash, old snapshots), and
System Settings had attached the grant to one of them. Switching a row off and on
keeps its code requirement; only removing it with − and adding it again replaces
it. The fallback card now says so. To check a machine:

```bash
sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" \
  "select hex(csreq) from access where service='kTCCServiceAccessibility' and client='com.keypath.KeyPath'" \
  | xxd -r -p > /tmp/r && csreq -r /tmp/r -t
```
