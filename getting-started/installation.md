---
layout: default
title: "Setting Up KeyPath"
description: "In two minutes your keyboard will launch apps, tile windows, and remap any key — all from the home row"
---


# Setting Up KeyPath

In two minutes, your keyboard will be able to launch apps, tile windows, fire shortcuts without reaching, and remap any key — all from the home row. This guide walks you through each step of the setup wizard and explains what's happening behind the scenes.

---

## What You'll Get

Once setup is complete, KeyPath gives you:

- **System-wide remapping** — Caps Lock becomes Escape, or a Hyper key, or anything you want
- **App launching** — Hold one key + press a letter to open any app instantly
- **Window tiling** — Snap windows to halves, thirds, or corners with a key combo
- **Home row shortcuts** — Your modifier keys live under your fingertips, not in the corner

Screenshot — The KeyPath overlay showing your active layout:
```
  ┌──────────────────────────────────────────────┐
  │  ● KeyPath                    Base Layer      │
  │                                               │
  │  ┌───┬───┬───┬───┬───┬───┬───┬───┬───┬───┐   │
  │  │ Q │ W │ E │ R │ T │ Y │ U │ I │ O │ P │   │
  │  ├───┼───┼───┼───┼───┼───┼───┼───┼───┼───┤   │
  │  │ A │ S │ D │ F │ G │ H │ J │ K │ L │ ; │   │
  │  ├───┼───┼───┼───┼───┼───┼───┼───┼───┼───┤   │
  │  │ Z │ X │ C │ V │ B │ N │ M │ , │ . │ / │   │
  │  └───┴───┴───┴───┴───┴───┴───┴───┴───┴───┘   │
  └──────────────────────────────────────────────┘
```

Want to see what's possible before you start? Check out [What You Can Build]({{ '/guides/use-cases' | relative_url }}).

---

## Before You Start

- **macOS 14 (Sonoma) or later** is required
- If you're running **Karabiner-Elements**, quit it first — it conflicts with KeyPath

> ⚠️ **Watch out:** Karabiner-Elements grabs the same low-level keyboard APIs that KeyPath needs. Quit it from the menu bar icon before continuing. You can always switch back later — see [From Karabiner-Elements]({{ '/migration/karabiner-users' | relative_url }}).

---

## The Setup Wizard

KeyPath's wizard opens automatically on first launch. It detects what's needed, walks you through each step, and checks your progress. This guide explains **what's happening and why** so nothing feels mysterious.

The wizard shows a **Setup Overview** with status indicators for each step. Green checkmarks mean done; orange or red icons mean action needed. Click **Fix** on any item to start that step.

---

## Step 1: Privileged Helper Installation

The wizard's first action step. KeyPath needs to install a small privileged helper service that runs in the background and manages the keyboard remapping engine. This requires your admin password.

**What happens:** macOS shows an authorization prompt. Enter your password and click **Install**. This is a one-time step — you won't be asked again unless you uninstall and reinstall.

Screenshot — macOS authorization prompt:
```
  ┌─────────────────────────────────────┐
  │  KeyPath wants to install a         │
  │  privileged helper.                 │
  │                                     │
  │  [Username]                         │
  │  [••••••••••]                       │
  │                                     │
  │      [ Cancel ]    [ Install ]      │
  └─────────────────────────────────────┘
```

> ⚠️ **Watch out:** Clicking **Cancel** stops the installation. KeyPath can't remap keys without the helper. If this happens, re-run the wizard from **File > Install wizard...** (Shift+Cmd+N).

After installation, macOS may also ask you to approve KeyPath in **Login Items** under System Settings. If prompted, find KeyPath under "Allow in the Background" and toggle it ON.

---

## Step 2: Enhanced Diagnostics (Optional)

The wizard calls this **"Enhanced Diagnostics."** Under the hood, it's macOS Full Disk Access — it lets KeyPath read the system permission database so it can accurately verify that all permissions are correctly set.

**Without it:** KeyPath still works, but some permission checks may show as "unverified" instead of a clear green checkmark or red X.

**With it:** Permission verification is precise, error messages are more helpful, and KeyPath can proactively detect issues.

> 💡 **Tip:** You can **Skip** this step. It's optional and you can always enable it later from System Settings > Privacy & Security > Full Disk Access.

---

## Step 3: Accessibility

**Why:** Accessibility permission lets KeyPath **send** remapped keystrokes to your apps. Without it, KeyPath can read your keys but can't write the new ones back.

This step has **two components** — both need to be granted:

### 3a: KeyPath.app

KeyPath.app usually appears in the Accessibility list automatically. Toggle it **ON**.

Screenshot — System Settings > Privacy & Security > Accessibility:
```
  ┌──────────────────────────────────────────────┐
  │  Privacy & Security > Accessibility          │
  │                                              │
  │  Allow the apps below to control             │
  │  your computer.                              │
  │                                              │
  │  ┌──────────────────────────────────┐        │
  │  │ 🔑 KeyPath.app          [  ●  ] │ ← ON   │
  │  └──────────────────────────────────┘        │
  │                                              │
  │          [ + ]                               │
  └──────────────────────────────────────────────┘
```

### 3b: The kanata binary (the tricky part)

KeyPath uses a separate engine called **kanata** to do the actual keyboard remapping. Because kanata is a system binary (not a regular .app), it **does not appear** in the Accessibility list automatically. You have to add it manually.

**When you click Fix** in the wizard, two things happen:
1. System Settings opens to the Accessibility pane
2. A Finder window opens showing the kanata binary so you can see where it lives

**Step by step:**

1. Click **Fix** next to "kanata" in the wizard
2. System Settings opens to Accessibility; Finder reveals the kanata binary at `/Library/KeyPath/bin/`
3. In System Settings, click the **+** button at the bottom of the app list
4. A file picker opens (it defaults to /Applications — kanata isn't there)
5. Press **Cmd+Shift+G** to open the "Go to Folder" sheet
6. Type `/Library/KeyPath/bin/kanata` and press **Enter**
7. Click **Open** to add kanata to the list
8. Toggle kanata **ON** in the list
9. Return to KeyPath — the wizard detects the change automatically

Screenshot — Using the + button and Go to Folder to find kanata:
```
  ┌─ System Settings ──────────────────────────────┐
  │                                                 │
  │  Privacy & Security > Accessibility             │
  │                                                 │
  │  ┌───────────────────────────────────────┐      │
  │  │ 🔑 KeyPath.app              [  ●  ]  │      │
  │  └───────────────────────────────────────┘      │
  │                                                 │
  │  [ + ] ◄── 1. Click this                        │
  │                                                 │
  │  ┌─ File Picker ──────────────────────────┐     │
  │  │                                        │     │
  │  │  Go to Folder: [/Library/KeyPath/bin/] │     │
  │  │                 ▲                      │     │
  │  │                 2. Cmd+Shift+G,        │     │
  │  │                    type this path      │     │
  │  │                                        │     │
  │  │  ┌────────────────────────────┐        │     │
  │  │  │ ⚙ kanata  ◄── 3. Select   │        │     │
  │  │  └────────────────────────────┘        │     │
  │  │                                        │     │
  │  │              [ Open ] ◄── 4. Click     │     │
  │  └────────────────────────────────────────┘     │
  └─────────────────────────────────────────────────┘
```

> ⚠️ **Watch out:** The kanata binary looks like a plain executable icon, not like an app. That's normal — it's a command-line binary, not a .app bundle. After you add it, it may appear as "kanata" with a generic Terminal-style icon in the list.

> 💡 **Tip:** The wizard also opens a Finder window showing kanata's location. This is for reference so you know you're adding the right file. The actual adding happens through the **+** button in System Settings.

---

## Step 4: Input Monitoring

**Why:** Input Monitoring lets KeyPath **read** which keys you press. This is the counterpart to Accessibility — together they form the read/write pair that makes remapping work. For a deeper look at why both are needed, see [Privacy & Permissions]({{ '/guides/privacy' | relative_url }}).

Same two-component process as Accessibility:

### 4a: KeyPath.app

KeyPath.app should appear in the Input Monitoring list. Toggle it **ON**.

### 4b: The kanata binary (same + button process)

Same process as Accessibility — kanata is a system binary and won't appear automatically.

1. Click **Fix** next to "kanata" in the wizard
2. System Settings opens to Input Monitoring; Finder reveals the kanata binary for reference
3. Click the **+** button in System Settings
4. Press **Cmd+Shift+G**, type `/Library/KeyPath/bin/kanata`, press Enter
5. Click **Open**, then toggle kanata **ON**
6. Return to KeyPath

Screenshot — System Settings > Privacy & Security > Input Monitoring after adding both:
```
  ┌──────────────────────────────────────────────┐
  │  Privacy & Security > Input Monitoring       │
  │                                              │
  │  Allow the apps below to monitor             │
  │  input from your keyboard.                   │
  │                                              │
  │  ┌──────────────────────────────────┐        │
  │  │ 🔑 KeyPath.app          [  ●  ] │ ← ON   │
  │  │ ⚙  kanata               [  ●  ] │ ← ON   │
  │  └──────────────────────────────────┘        │
  │                                              │
  │          [ + ]                               │
  └──────────────────────────────────────────────┘
```

> ⚠️ **Watch out:** macOS cannot grant these permissions automatically. No app can flip its own toggles — Apple requires you to do it manually in System Settings. The wizard opens the right pane and shows you the binary, but the clicking and dragging is up to you.

> 💡 **Tip:** After granting permissions, macOS sometimes needs KeyPath to restart before it recognizes the change. If the wizard still shows a warning after toggling, try quitting KeyPath (Cmd+Q) and reopening it.

---

## Step 5: Kanata Engine Setup

The wizard verifies that the kanata remapping engine is properly installed at `/Library/KeyPath/bin/kanata`. This step is usually automatic — the privileged helper installed it in Step 1.

If something went wrong (file missing or corrupted), click **Fix** and the wizard reinstalls it.

---

## Step 6: Start Keyboard Service

The final step. The wizard starts the kanata service that runs in the background. Once it's running, your key remappings are active system-wide.

The wizard shows a live status indicator:

- **Green checkmark** — Service is running
- **Orange** — Service is stopped
- **Red** — Service failed (check logs in **File > Logs...**)

---

## Verify It's Working

After the wizard completes and returns to the **Setup Overview** with all green checkmarks, look at the overlay in the bottom-center of your screen:

Screenshot — Overlay header with green health indicator:
```
  ┌──────────────────────────────────────────────┐
  │  ● KeyPath                    Base Layer      │
  └──────────────────────────────────────────────┘
       ▲
       Green dot = service running, permissions OK
```

**Quick test:** The default configuration maps **Caps Lock to Escape**. Press Caps Lock — if it fires Escape (try it in a text field or Terminal), remapping is active.

---

## If Something Went Wrong

| Problem | Fix |
|---------|-----|
| Kanata doesn't appear in Finder when clicking Fix | The binary may not be installed yet. Go back to the Kanata Engine Setup step and click Fix to install it first. |
| Dragged kanata to the list but it didn't appear | Try the **+** button instead: click +, press Cmd+Shift+G, type `/Library/KeyPath/bin/kanata`, press Enter, click Open. |
| Toggle is ON but wizard still shows a warning | Quit KeyPath completely (Cmd+Q), reopen it. macOS sometimes needs a fresh app launch to recognize new permissions. |
| Service not starting (red indicator) | Open **File > Install wizard...** and re-run the Privileged Helper step. |
| Karabiner conflict detected | The wizard's Resolve Conflicts step handles this — click Fix to quit conflicting processes. Or quit Karabiner-Elements from its menu bar icon manually. |
| KeyPath.app doesn't appear in permission lists | Restart your Mac. In rare cases macOS needs a reboot to register new apps in Privacy settings. |
| Permissions granted but keys aren't remapped | Check the overlay — is it showing "Base Layer"? If so, the service is running but your config may not have rules yet. Try the Caps Lock to Escape test above. |

> 💡 **Tip:** You can always re-run the setup wizard from **File > Install wizard...** (Shift+Cmd+N). It picks up where you left off and only shows steps that still need attention.

---

## What's Next

You're set up! Here are the best places to go from here:

- [Keyboard Concepts]({{ '/guides/concepts' | relative_url }}) — Layers, tap-hold, and the ideas behind modern keyboard customization
- [What You Can Build]({{ '/guides/use-cases' | relative_url }}) — Real examples: app launching, window tiling, Vim-style navigation
- [Shortcuts Without Reaching]({{ '/guides/home-row-mods' | relative_url }}) — Turn your home row into modifier keys so you never leave home position

---

## Resources

- [Apple: Control access to Input Monitoring on Mac](https://support.apple.com/guide/mac-help/control-access-to-input-monitoring-on-mac-mchl4cedafb6/mac) ↗
- [Apple: Allow Accessibility apps to access your Mac](https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/mac) ↗
- [Karabiner-Elements: Uninstalling](https://karabiner-elements.pqrs.org/docs/manual/uninstall/) ↗
