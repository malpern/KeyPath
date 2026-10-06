---
layout: default
title: "Installation Wizard"
description: "What to expect when setting up KeyPath for the first time"
theme: parchment
header_image: header-installation-wizard.png
permalink: /guides/installation-wizard/
---

# Set up KeyPath

The driverless version runs while you are signed in. It needs **Accessibility**
and **Input Monitoring**, without installing a keyboard driver or privileged
remapping service. Full Disk Access is not requested.

## First launch

1. Open KeyPath and choose **Get Started**.
2. Follow the wizard to enable KeyPath in **System Settings → Privacy & Security → Accessibility**.
3. Enable KeyPath in **Input Monitoring**. macOS may ask for your password and require you to quit and reopen KeyPath.
4. Return to KeyPath and start the runtime. When KeyPath is ready, choose **Open Rules**.

The wizard checks the permissions and runtime rather than treating a Settings
toggle as proof that remapping has started. If startup is blocked, follow the
message shown in KeyPath.

## Caps Lock can do two jobs

With Caps Lock remapping enabled, a quick tap can send Escape and a hold can act
as a modifier, such as Control or Hyper. Choose the behavior in Rules.

In **Settings → General → Caps Lock Remapping**, review your keyboard and
explicitly reserve F18 before enabling setup. Select the keyboard again after
restarting your Mac. If you use F18, leave this setup disabled.
See [Caps Lock and F18]({{ '/guides/driverless-caps-lock/' | relative_url }})
for keyboard eligibility, recovery and behavior details.

## Run setup again

Choose **File → Set Up KeyPath…**, or use the setup action in KeyPath’s menu-bar
menu. Setup helps with missing permissions or a runtime that has not started.

## Updates and removal

Choose **Download Update** to open the official releases page. Quit KeyPath
before replacing the app. Your rules are stored separately and are kept.

To remove the driverless app, quit KeyPath and move KeyPath.app to the Trash.
**Settings → Repair/Remove** also provides configuration backups and the Simulator.
This build does not remove older system services or a driver installed by another
app. Keep any Karabiner-Elements driver used by Karabiner-Elements.

## When remapping is unavailable

KeyPath does not remap protected password-entry or Secure Input contexts, or the
login screen. Do not rely on a remapped key to enter a password. Check KeyPath’s
status before relying on remapping after a permissions change or keyboard change.

See [Privacy and permissions]({{ '/guides/privacy/' | relative_url }}) for more.
