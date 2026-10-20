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

The saved selection identifies one keyboard for the current boot. After a
restart of your Mac it is never reused: automatic setup discovers an eligible
keyboard again, which only happens when exactly one compatible keyboard is
connected. With several, KeyPath asks you to choose again. Unplugging and
replugging during the same boot is covered below.

## Unplugging the chosen keyboard

macOS removes the Caps Lock mapping together with the keyboard, so nothing is
left behind. KeyPath keeps running: all your other rules keep working, and
Caps Lock rules pause until a keyboard is chosen again.

```text
Status

  Keyboard remapping
  Running normally. cl80 was disconnected. Caps Lock rules are paused;
  your other rules keep working. Choose a keyboard in Settings > General
  to turn them back on.

Settings → General

  ⇪  Caps Lock remapping                              [ On ]
     cl80 is disconnected · Caps Lock rules are paused; choose a keyboard
       Keyboard: [ Choose a keyboard ▾ ]
```

Plug it back into the **same USB port** and KeyPath picks it up again by
itself within a few seconds: Caps Lock rules turn back on, with the same
reserved key, and KeyPath says **cl80 was reconnected. Caps Lock rules are back
on.** KeyPath treats it as the same keyboard only when all of this holds:

- it is the same boot (a restart of your Mac always asks again),
- the vendor, product and USB port match the keyboard you chose, and so does
  the serial number when the keyboard has one,
- exactly one connected keyboard matches. Two identical keyboards that look
  the same to macOS are never guessed between.

Plugged into a **different port**, it counts as a different keyboard. Settings
then reads **cl80 is connected to a different port · Choose it again to turn
Caps Lock rules back on**; pick it from the menu.

If only one compatible keyboard is left after the unplug, KeyPath uses that one
automatically, the same as at startup, and says so: **cl80 was disconnected.
Caps Lock rules now apply to Built-in keyboard.** Plugging the cl80 back into
the same port moves them back to it. Choosing a keyboard yourself in Settings
in the meantime replaces that claim.

While Caps Lock rules are paused, Caps Lock on every keyboard works as a normal
Caps Lock key. The same happens when you turn **Caps Lock remapping** off, or
when more than one keyboard is connected and none is chosen yet: rules that use
Caps Lock don't run, and every other rule does.

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

Disabling setup preserves your rules. Rules that use physical Caps Lock stay
paused until setup is on again; your other rules keep running.

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
