---
layout: default
title: "Caps Lock in driverless KeyPath"
description: "Caps Lock rules across keyboards, keyboard exceptions, and compatibility"
permalink: /guides/driverless-caps-lock/
---

# Caps Lock in driverless KeyPath

Add a Caps Lock rule in **Rules**, such as Escape on tap and Hyper on hold.
KeyPath applies the same rule to every compatible connected keyboard by default.
There is no keyboard to choose before the rule works. A keyboard connected later
is set up automatically once all keys are released.

If you previously chose one keyboard for Caps Lock, KeyPath keeps that choice
when you upgrade. Use **Settings → General → Caps Lock options → Use Caps Lock
rules on all keyboards** to switch to the new default. You can also choose
**Use on one keyboard only** there and select a keyboard from the picker.

## Make an exception for one keyboard

Open **Settings → General → Caps Lock rules → Caps Lock options**. Turn
off **Use on [keyboard name]** to leave that keyboard's Caps Lock key alone.
Other keyboards continue using the rule. Turn it back on to resume. The
exception follows a keyboard reconnected at the same port, with the same
serial number when one is available. Moving it to another port makes it a new
keyboard for this preference.

This setting controls whether a keyboard's Caps Lock enters KeyPath's rule
engine. Different Caps actions on different keyboards are not yet available in
driverless mode: macOS does not include a dependable keyboard identity in the
event stream KeyPath uses for ordinary rules.

## Why a function key is involved

macOS toggles Caps Lock before KeyPath's driverless keyboard event handler can
stop it. KeyPath changes physical Caps Lock to a spare function key **on each
keyboard**, then handles that key as the Caps Lock input to your rule:

```text
Physical Caps Lock → spare function key → your Caps Lock rule
```

KeyPath starts with F18 and can choose another key from F13–F20 when a rule,
another mapping, or a macOS shortcut uses it. The spare key is shared across
the participating keyboards. A physical press of that same function key cannot
be distinguished from remapped Caps Lock while Caps rules are running.

KeyPath saves each keyboard's original macOS mapping before changing it and
restores each mapping when the keyboard session ends. An unplugged keyboard's
mapping disappears with that device. A recovery record is retained if a
mapping cannot be restored safely.

## A keyboard could not be used

Settings names a keyboard whose Caps Lock setup is unavailable; rules on other
keyboards keep working. KeyPath does not replace an existing Caps Lock mapping
from **System Settings → Keyboard → Modifier Keys** or another app such as
Raycast. Remove that conflicting mapping if you want KeyPath to control Caps
Lock on that keyboard, then choose **Check Again**.

Some keyboards expose several interfaces, including one labeled as a mouse for
N-key rollover. KeyPath covers every interface it can verify may send keys.
If it cannot determine the covered interfaces safely, that keyboard is left
uncovered rather than guessing. Virtual keyboards are not physical Caps Lock
targets.

The first Caps Lock press immediately after plugging in a keyboard can arrive
before macOS finishes presenting the device for setup. If Caps Lock behaves
normally at that moment, release all keys and try again after KeyPath reports
the keyboard as active. Protected password fields and Secure Input still
prevent dynamic remapping.

## Can a rule turn Caps Lock on?

Yes. A rule whose **output** is Caps Lock uses macOS's native lock state. That
is separate from remapping the physical Caps Lock **input** described above.
