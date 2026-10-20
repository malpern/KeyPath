---
layout: default
title: "Caps Lock in driverless KeyPath"
description: "Automatic Caps Lock setup, F18 reservation, and keyboard compatibility"
permalink: /guides/driverless-caps-lock/
---

# Caps Lock in driverless KeyPath

Choose a Caps Lock rule in **Rules**, such as Escape on tap and Hyper on hold.
KeyPath prepares Caps Lock automatically when it can identify exactly one
compatible keyboard and automatic setup is enabled. You do not normally need
to select a keyboard before using the tour.

If setup cannot identify one compatible keyboard, open **Settings → General**
to review Caps Lock setup. A virtual keyboard in a VM is not a compatible
physical keyboard. KeyPath refuses ambiguous setup rather than choosing a
device arbitrarily.

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
it does not trust an old device identifier after reconnect or reboot. Exactly
one compatible keyboard is required for automatic selection.

KeyPath checks existing mappings and ownership before changing or restoring
them. Conflicting mappings are refused. If safe restoration cannot be verified,
the recovery record is retained and restart can be blocked. Follow the displayed
recovery instructions instead of overwriting another mapping.

Disabling setup preserves your rules. A configuration that still uses physical
Caps Lock needs setup enabled again, or a different trigger.

## Other limitations

- Managed Caps setup does not promise arbitrary multi-keyboard behavior.
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
