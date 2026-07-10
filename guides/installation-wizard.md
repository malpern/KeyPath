---
layout: default
title: "Installation Wizard"
description: "What to expect when setting up KeyPath for the first time"
theme: parchment
header_image: header-installation-wizard.png
permalink: /guides/installation-wizard/
---

# Installation Wizard

The first time you open KeyPath, a setup wizard walks you through everything needed to get keyboard remapping working. It takes about two minutes, and you'll grant a few permissions along the way.

This guide explains what each step does and why it's needed, so you know what you're agreeing to.

---

## Overview

KeyPath needs three things from macOS to remap your keyboard:

1. **A helper tool** — installs a privileged component that manages the keyboard driver
2. **Accessibility permission** — lets KeyPath read which keys you press
3. **Input Monitoring permission** — lets KeyPath intercept and remap key events

The wizard checks each of these and walks you through granting them. If everything is already set up (e.g., you reinstalled KeyPath), the wizard skips completed steps automatically.

---

## Step by step

### 1. Helper installation

The wizard starts by installing a privileged helper tool. macOS will show a system dialog asking for your password or Touch ID — this is the standard macOS authorization prompt for installing system components.

```
  ┌─────────────────────────────────────────────────┐
  │  KeyPath needs to install a helper tool         │
  │                                                  │
  │  This helper manages the keyboard driver and    │
  │  runs the remapping service. macOS will ask     │
  │  for your password.                             │
  │                                                  │
  │                          [ Install Helper ]      │
  └─────────────────────────────────────────────────┘
```

**Why it's needed:** The keyboard driver runs at the system level. A helper tool with elevated privileges is required to manage it safely.

### 2. Accessibility permission

macOS asks you to grant KeyPath Accessibility access in System Settings. The wizard shows you exactly where to click.

**Why it's needed:** Accessibility access lets KeyPath see which keys you press, so it can decide what to do with them (remap, activate a layer, trigger an action).

### 3. Input Monitoring permission

Similar to Accessibility — macOS asks you to grant Input Monitoring access.

**Why it's needed:** Input Monitoring lets KeyPath intercept key events before they reach your apps. This is what makes remapping work — KeyPath catches the physical key, transforms it, and sends the remapped key to your app.

### 4. Karabiner import (if applicable)

If you have Karabiner-Elements installed, the wizard offers to import your existing rules. You can review which rules will convert and choose which to import.

See [Switching from Karabiner]({{ '/migration/karabiner-users/' | relative_url }}) for details on what converts.

### 5. Start service

The wizard starts the Kanata remapping engine. Once it's running, your keyboard remapping is active — Home Row Arrows and any other default packs work immediately.

```
  ┌─────────────────────────────────────────────────┐
  │                                                  │
  │  ✅  KeyPath is ready                            │
  │                                                  │
  │  Your keyboard remapping is active.             │
  │  Home Row Arrows is on — hold F for arrow keys. │
  │                                                  │
  │                            [ Get Started ]       │
  └─────────────────────────────────────────────────┘
```

---

## If something goes wrong

The wizard is designed to handle problems gracefully:

**Permission denied:** If you decline a permission, the wizard explains what won't work and lets you try again. You can also grant permissions later in **System Settings > Privacy & Security**.

**Karabiner conflict:** If Karabiner-Elements is running, the wizard asks you to quit it first. Both tools can't intercept the keyboard at the same time.

**Helper installation fails:** Usually a macOS authorization issue. Try again — if it persists, check that you're an admin user on this Mac.

**Service won't start:** The wizard runs diagnostics and shows what's blocking the service. Common causes: permissions not granted, driver not installed, or a conflicting process.

### Running the wizard again

If you need to re-run the wizard (e.g., after a macOS update that reset permissions):

1. Open KeyPath
2. Go to **File > Installation Wizard**

Or from the menu bar icon: click the KeyPath icon → **Setup Wizard**.

### Uninstalling KeyPath

Open **Settings > Repair/Remove** and choose **Uninstall**. KeyPath normally uses
its existing system helper to remove the app and its background services without
another password prompt. If that helper is unavailable, KeyPath first repairs it
using macOS Service Management and retries the uninstall.

KeyPath does not automatically run a backup administrator script. If the helper
cannot be repaired, the uninstall dialog offers **Emergency Cleanup** as a separate
action and explains that macOS will request an administrator password. KeyPath
checks that the requested components are actually gone before reporting success.

The virtual keyboard driver is shared with tools such as Karabiner-Elements, so
removing it is optional. When selected, KeyPath verifies the driver separately and
stops before removing KeyPath if macOS leaves the driver registered. You can retry,
or uncheck driver removal to remove KeyPath while preserving the shared driver.

---

## What runs in the background

After setup, KeyPath runs two components:

| Component | What it does | When it runs |
|-----------|-------------|-------------|
| **Kanata service** | The remapping engine — intercepts and transforms key events | Always (LaunchDaemon, starts at boot) |
| **KeyPath app** | The UI — overlay, settings, pack gallery | When you open it |

The Kanata service runs as a LaunchDaemon, which means your remapping works even if you haven't opened the KeyPath app — it starts when your Mac boots. The KeyPath app is just the visual interface for configuration.

You can control the service from the menu bar icon or the [CLI]({{ '/guides/cli/' | relative_url }}):

```bash
keypath status     # Check if everything is healthy
keypath restart    # Restart the remapping service
keypath stop       # Stop remapping (keys go back to normal)
```

---

## Privacy

KeyPath needs low-level keyboard access to work, but:

- **No keystrokes are recorded or transmitted.** KeyPath transforms keys in real time and discards them.
- **No network access.** The remapping engine runs entirely on your Mac.
- **No analytics.** KeyPath doesn't phone home.

See [Privacy & Permissions]({{ '/guides/privacy/' | relative_url }}) for the full details.

---

## Related guides

- **[Setting Up KeyPath]({{ '/getting-started/installation/' | relative_url }})** — Download and install
- **[Remapping]({{ '/guides/remapping/' | relative_url }})** — Your first remap after setup
- **[Switching from Karabiner]({{ '/migration/karabiner-users/' | relative_url }})** — Import your existing config
- **[Privacy & Permissions]({{ '/guides/privacy/' | relative_url }})** — What KeyPath can and can't see
