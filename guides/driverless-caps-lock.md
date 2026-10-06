---
layout: default
title: "Caps Lock in driverless KeyPath"
description: "How the experimental Caps Lock remap uses F18, and what that means for your shortcuts"
permalink: /guides/driverless-caps-lock/
---

# Caps Lock in driverless KeyPath

**Current status (October 6, 2026): experimental, DEBUG-only.** This is not yet
an ordinary production setup option. Physical basic remapping and tap/hold have
worked in the lab, but broader keyboard compatibility and recovery coverage are
still required before enabling it for everyone.

## Why F18 is involved

Caps Lock changes macOS's Caps Lock state before KeyPath's normal driverless
keyboard interception point. Treating it like an ordinary key there is not enough.
The experimental workaround uses a macOS mapping on one selected keyboard:

```text
Physical Caps Lock → macOS substitutes F18 → KeyPath interprets logical Caps Lock
                                             → Kanata applies your Caps rule
                                             → e.g. Escape on tap, Control on hold
```

F18 is an internal intermediate key, not the action you are choosing. You still
configure a Caps Lock rule; you do not need to write an F18 rule. This approach
does not install the Karabiner driver or require Full Disk Access. Accessibility
and Input Monitoring remain part of driverless setup.

## What if I use F18?

**The current managed-Caps experiment reserves F18.** At the interception point,
a real F18 event is indistinguishable from Caps Lock that macOS changed into F18.
Using both would risk making your real F18 key perform your Caps Lock action.
The device-specific macOS mapping does not give the later event stream reliable
keyboard identity.

The experiment requires an explicit declaration that F18 is reserved, checks
existing device mappings for conflicts, and rejects native F18 input/output in a
managed-Caps configuration. These checks cannot discover every shortcut in other
apps or prove that another device will never send F18.

If you need F18, keep managed Caps disabled and use another supported key for your
remap. F18 is not globally removed from KeyPath: ordinary driverless profiles
without managed Caps can still use it. There is currently no automatic switch to
F19, F20, or another intermediate key.

## Other boundaries

- The prototype admits one eligible physical keyboard, explicitly selected. It
  does not promise arbitrary multi-keyboard or reconnect support.
- Existing Caps mappings or mappings using F18 on that device cause refusal;
  KeyPath does not silently overwrite them.
- Managed mode does not support emitting Caps Lock or F18 as output. Recipes such
  as double-tap to restore Caps Lock are not covered by this experiment.
- Protected password fields and Secure Input do not gain dynamic remapping from
  this workaround. Do not rely on a Caps remap for password entry.
- KeyPath records the original device mapping and checks ownership before
  restoring it. Uncertain recovery or someone else's changed mapping can block
  restart instead of being overwritten. Crash, reconnect, and reboot handling
  are not universally verified.

## Should KeyPath choose another intermediate key automatically?

**Recommendation: keep F18 fixed for the first supported version.** Explain a
conflict when enabling Caps remapping, preserve the user's existing shortcuts,
and offer another trigger key. Keep this detail out of ordinary onboarding when
Caps remapping is not being enabled.

If demand justifies it later, add a small advanced choice of explicitly supported
intermediate keys, selected while remapping is stopped. Validate the choice and
save it with the configuration and recovery record. That would preserve F18 for
users who need it without silently changing their setup.

Automatic reassignment is deferred. An apparently unused key in KeyPath may have
an important shortcut in another app. Changing it also requires coordinated
updates to macOS's mapping, input interpretation, configuration validation, and
crash recovery. This is more than replacing one constant, and live switching
while a key is held would add unnecessary risk.
