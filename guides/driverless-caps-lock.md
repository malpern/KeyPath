---
layout: default
title: "Caps Lock in driverless KeyPath"
description: "Automatic Caps Lock setup, F18 reservation, and keyboard compatibility"
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
reads **On · cl80** (or whichever you chose). Caps Lock on your other keyboards
keeps working as a normal Caps Lock key. You can change the choice at any time
from the same menu.

A virtual keyboard in a VM is not a compatible physical keyboard and is not
listed.

## Why F18 is involved

Caps Lock changes macOS's lock state before ordinary driverless interception.
KeyPath uses a macOS mapping on the selected keyboard:

```text
Physical Caps Lock → macOS substitutes F18 → KeyPath applies your Caps Lock rule
```

F18 is an internal intermediate key. Configure a Caps Lock rule, not an F18
rule. This does not install a keyboard driver or require Full Disk Access.
Accessibility is used by driverless setup; a separate Input Monitoring step is not required in the tested flow.

## What if I use F18?

**Managed Caps remapping reserves F18.** A real F18 event cannot be reliably
distinguished from Caps Lock that macOS changed into F18. Managed configurations
therefore reject native F18 input and output.

If you need F18, disable managed Caps setup and use another trigger key.
Ordinary configurations without managed Caps can still use F18. KeyPath does
not automatically select another intermediate key.

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

KeyPath checks existing mappings and ownership before changing or restoring
them. Conflicting mappings are refused. If safe restoration cannot be verified,
the recovery record is retained and restart can be blocked. Follow the displayed
recovery instructions instead of overwriting another mapping.

Disabling setup preserves your rules. A configuration that still uses physical
Caps Lock needs setup enabled again, or a different trigger.

## Other limitations

- Caps Lock rules apply to one chosen keyboard at a time. F18 stays reserved
  on every keyboard, because KeyPath cannot tell which keyboard sent it.
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
