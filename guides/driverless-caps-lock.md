---
layout: default
title: "Caps Lock in driverless KeyPath"
description: "Automatic Caps Lock setup, the reserved function key, conflicts with other apps, and keyboard compatibility"
permalink: /guides/driverless-caps-lock/
---

# Caps Lock in driverless KeyPath

Choose a Caps Lock rule in **Rules**, such as Escape on tap and Hyper on hold.
KeyPath prepares Caps Lock automatically when exactly one compatible keyboard
is connected and automatic setup is enabled. You do not normally need to
select a keyboard before using the tour.

## More than one keyboard

A MacBook with an external keyboard has two keyboards. KeyPath does not guess
which one you mean, so a Caps Lock rule stays inactive until you choose:

```text
Settings → General

  ⇪  Caps Lock remapping                              [ On ]
     Choose which keyboard Caps Lock rules apply to
       Keyboard: [ Choose a keyboard ▾ ]
                   Built-in keyboard
                   cl80
```

Pick the keyboard whose Caps Lock key you want to remap. The status line then
reads **On · cl80 · Uses F18 behind the scenes** (with your keyboard's name,
and whichever key KeyPath reserved; see below). Caps Lock on your other keyboards
keeps working as a normal Caps Lock key. You can change the choice at any time
from the same menu.

A virtual keyboard in a VM is not a compatible physical keyboard and is not
listed.

## Why a function key is involved

Caps Lock changes macOS's lock state before ordinary driverless interception.
KeyPath uses a macOS mapping on the selected keyboard:

```text
Physical Caps Lock → macOS substitutes F18 → KeyPath applies your Caps Lock rule
```

The function key is an internal stand-in. Configure a Caps Lock rule, not a
rule for that key. This does not install a keyboard driver or require Full Disk
Access. Accessibility is used by driverless setup; a separate Input Monitoring
step is not required in the tested flow.

## Which key is reserved

KeyPath reserves one key from **F13 to F20** while Caps Lock rules are on. It
starts with F18. Settings shows the current one:

```text
Settings → General

  ⇪  Caps Lock remapping  ⓘ                           [ On ]
     On · cl80 · Uses F19 behind the scenes
```

A real press of the reserved key cannot be told apart from Caps Lock that
macOS changed into it, so KeyPath avoids any key that is already in use. Each
time KeyPath starts its keyboard session it checks, and moves to the next free
key when the current one is taken by:

- one of your rules (for example a Caps Lock → F18 rule, or a rule triggered by F18),
- another app's macOS key mapping on any keyboard, or
- a shortcut in **System Settings → Keyboard → Keyboard Shortcuts**.

You do not need to do anything when it moves. If every key from F13 to F20 is
in use, KeyPath says so and Caps Lock rules stay off until one is free.
F21 to F24 cannot be used: macOS gives them no key code, so KeyPath would
never see them.

## Can I still turn Caps Lock on?

Yes. Caps Lock output uses the native macOS lock state. Backup Caps Lock and
multi-tap rules can toggle it; holding or repeating that output does not
repeatedly toggle the state. This is distinct from remapping the physical
Caps Lock input, which needs compatible keyboard setup.

## Restarts and connected keyboards

The saved selection identifies one keyboard instance for the current boot.
When it becomes stale, automatic setup can discover an eligible keyboard again;
it does not trust an old device identifier after reconnect or reboot. Automatic
selection only happens when exactly one compatible keyboard is connected. With
several, KeyPath asks you to choose again after a restart. If you unplug the
chosen keyboard and KeyPath restarts while only one keyboard remains, it uses
that one; when you plug yours back in, pick it again from the menu in
**Settings → General**.

Some keyboards can't be chosen. Virtual keyboards from other remapping tools
(such as Karabiner-Elements) and virtual machines are left out of the list.
A keyboard that macOS shows as several keyboard devices, or one KeyPath does
not recognize, is also left out, because KeyPath cannot change only that one;
Settings says how many were left out. While such a keyboard is connected,
KeyPath does not choose for you, even if only one keyboard is in the list.

KeyPath checks existing mappings and ownership before changing or restoring
them. Conflicting mappings are refused.

## Another app already uses Caps Lock

Only one app can remap Caps Lock on a keyboard this way. When another app got
there first, Settings says which one when KeyPath can tell:

```text
Settings → General

  ⇪  Caps Lock remapping                              [ On ]
     On · cl80 · Uses F18 behind the scenes
     Raycast's Hyper Key is using Caps Lock. Turn it off in Raycast,
     or use another trigger for Hyper Key.
```

- **Raycast Hyper Key**: in Raycast's settings, turn Hyper Key off or give it
  another key. Raycast's Hyper Key remaps Caps Lock on
  every keyboard, so it conflicts whichever keyboard you choose. KeyPath can do
  the same job: a Caps Lock rule with Hyper on hold.
- **Something else**: KeyPath names the key Caps Lock was changed to when it
  can. Check other keyboard apps, and **System Settings → Keyboard → Keyboard
  Shortcuts → Modifier Keys**, which can also change Caps Lock.

KeyPath never removes another app's mapping. Once it is gone, choose
**Check Again** or reopen Settings. If safe restoration cannot be verified,
the recovery record is retained and restart can be blocked. Follow the displayed
recovery instructions instead of overwriting another mapping.

Disabling setup preserves your rules. A configuration that still uses physical
Caps Lock needs setup enabled again, or a different trigger.

## Other limitations

- Caps Lock rules apply to one chosen keyboard at a time. The reserved key
  (F18 unless KeyPath moved it) stays reserved on every keyboard, because
  KeyPath cannot tell which keyboard sent it.
- Protected password fields and Secure Input do not gain dynamic remapping.
  Do not rely on a Caps remap for password entry.
- Media and brightness remapping remain unavailable in driverless mode.
  Your keyboard's normal media controls remain managed by macOS.

## Validation status

The current implementation includes automatic selection and native Caps Lock
output. These describe code behavior, not a completed hardware certification.
Physical USB qualification of the current candidate, including reconnect and
restart recovery, remains a release gate. Earlier physical tests do not
substitute for testing this candidate.

## Updating KeyPath

Choose **Download Update…**, download the new app, then quit KeyPath before
replacing it. Your rules are kept. This driverless version uses manual downloads.
