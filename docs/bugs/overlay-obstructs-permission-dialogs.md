# Floating overlay obstructs permission dialogs

## Evidence

The October 15 lifecycle VM run showed the faded keyboard overlay intercepting a
click intended for Cancel in a System Settings authentication dialog. The runtime
had stopped, but logs still reported Accessibility granted; this was not proof
of a completed revocation. Evidence is retained under
`~/keypath-review-evidence/20261014-onboarding-review/lifecycle/`.

The overlay uses a floating window that accepts mouse events even after its
content fades. Fading is visual only. The existing app suppressor previously
consulted only user exclusions, so default setup did not hide the overlay over
System Settings.

## Fix

Reuse app activation suppression for `com.apple.systempreferences` and
`com.apple.SecurityAgent`, without changing user exclusions. Restore previous
visibility when the foreground app changes. Block overlay show/bring-forward and
automatic-show requests while suppression is active. No additional permission,
process polling, authentication automation, or window-level change is required.

## Verification boundary

Focused tests cover built-in suppression and unchanged user exclusions.
A live VM must still verify Settings → authentication → return, including a layer
change while suppressed and restoration afterward. This is not a blanket guarantee
for every macOS secure-input window. The native-menu input issue, launch-at-login,
and uninstall/reinstall acceptance remain separate open checks.

## Race review follow-up

Launcher activation now checks suppression before activating KeyPath. Suppressed
hides are immediate; animation completions use a generation token so an older
hide cannot hide a subsequently restored window. Settings restore intent transfers
through suppression, while an explicit user hide is not restored. Three focused
tests and the signed release build pass. Live acceptance remains blocked by the
VM public-console prerequisite; see the October 15 lifecycle review.

## October 15 live follow-up

The public-console prerequisite is resolved for the completed lease
`cbx_b726c029cb77`. Normal Accessibility consent succeeded. With the runtime active,
two System Settings → Finder focus round trips hid and restored the overlay, and
the inspector drawer opened. Permission revocation and restoration also propagated
to app health, through its existing 60-second fallback refresh.

This closes basic live Settings suppression/restoration. Authentication while an
already-active overlay is present and layer changes during suppression remain
unverified; the first consent occurred before the overlay was active. See
`docs/testing/lifecycle-review-2026-10-15.md` for exact candidate and evidence paths.
