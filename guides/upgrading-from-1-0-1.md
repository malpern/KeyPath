---
layout: default
title: "Upgrading from KeyPath 1.0.1"
description: "Remove the old background keyboard service after updating from KeyPath 1.0.1"
permalink: /guides/upgrading-from-1-0-1/
---

# Upgrading from KeyPath 1.0.1

KeyPath 1.0.1 ran its keyboard engine as a background system service, with a
helper and the Karabiner virtual keyboard driver. Newer versions run while you
are signed in and need none of that. Both cannot change your keyboard at the
same time, so the new version will not start while the old service is running.

## Remove the old service

1. Open **Settings → Status**. It shows
   **The keyboard service from KeyPath 1.0.1 is still running.**
2. Choose **Remove Old Service**.
3. Enter your administrator password when macOS asks. You are asked once.

```
┌ Keyboard remapping ──────────────────────────────────────────┐
│ Runtime is stopped. The keyboard service from KeyPath 1.0.1   │
│ is still running. Remove it to start KeyPath.                 │
│                                                               │
│ [Remove Old Service]  [Open System Settings]  [Open Wizard]   │
└───────────────────────────────────────────────────────────────┘
```

KeyPath stops the old service, removes it and its helper, checks that neither
is still running, and then starts. Your rules are kept.

If you cancel the password prompt, nothing is removed. Choose
**Remove Old Service** again when you are ready.

If KeyPath says the service was removed but it still detects it, restart your
Mac and open KeyPath again.

## The Karabiner virtual keyboard driver

KeyPath does not remove the Karabiner driver. Karabiner-Elements uses the same
driver, and removing it would break that app. After the cleanup, KeyPath tells
you whether the driver is still installed.

If you do not use Karabiner-Elements and want the driver gone, open Terminal and run:

```
/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager deactivate
```

macOS may ask you to approve the change. To remove the driver's remaining files, follow the uninstall steps in the
[Karabiner-DriverKit-VirtualHIDDevice instructions](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice).
