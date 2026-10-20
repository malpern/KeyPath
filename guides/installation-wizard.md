---
layout: default
title: "Installation Wizard"
description: "What to expect when setting up KeyPath for the first time"
theme: parchment
header_image: header-installation-wizard.png
permalink: /guides/installation-wizard/
---

# Set up KeyPath

The driverless version runs while you are signed in and uses **Accessibility**
to apply mappings. Setup does not install a keyboard driver or request Full Disk
Access. A separate Input Monitoring step is not part of this setup.

## First launch

1. Open the downloaded disk image and drag **KeyPath** to **Applications**.
2. Open KeyPath from Applications and choose **Get Started**.
3. Follow the wizard to enable KeyPath in **System Settings → Privacy & Security → Accessibility**. macOS may ask for your password.
4. Return to KeyPath. Remapping starts automatically, then the keyboard tour walks you through your first mapping.

If you opened the app from Downloads or the disk image, move it to Applications
and reopen it before granting access. If startup fails, KeyPath shows recovery
instructions instead of asking you to start the runtime as a routine setup step.

## Caps Lock can do two jobs

The tour can set up Escape on a quick Caps Lock tap and Hyper when held, then
help you make a shortcut. KeyPath prepares a compatible keyboard automatically.
If it cannot, use **Settings → General → Keyboard Setup** to review the keyboard.
See [Caps Lock and F18]({{ '/guides/driverless-caps-lock/' | relative_url }})
for compatibility, the F18 reservation, and recovery details.

## Keep mappings available after login

Enable **Launch at login** in **Settings → General → Startup**. It is optional.
If macOS needs approval, KeyPath offers **Open Login Items**. This starts KeyPath
after you sign in; it does not remap the login screen or protected password fields.

## Run setup again

Choose **File → Set Up KeyPath…**, or use the setup action in KeyPath’s menu-bar
menu. Setup helps with missing permissions or a runtime that has not started.

## Updates and removal

Choose **Download Update** to open the official releases page. Quit KeyPath
before replacing the app. Your rules are stored separately and are kept.

Use **Settings → Repair/Remove → Uninstall KeyPath** to back up your settings
to Downloads, remove your rules and preferences, disable launch at login, and
move the app to the Trash. Reinstalling after this starts onboarding again.
Moving only the app to the Trash leaves your rules and preferences behind.
This build does not remove older system services or a driver installed by another
app. Keep any Karabiner-Elements driver used by Karabiner-Elements.

## When remapping is unavailable

KeyPath does not remap protected password-entry or Secure Input contexts, or the
login screen. Do not rely on a remapped key to enter a password. Check KeyPath’s
status before relying on remapping after a permissions change or keyboard change.

See [Privacy and permissions]({{ '/guides/privacy/' | relative_url }}) for more.
