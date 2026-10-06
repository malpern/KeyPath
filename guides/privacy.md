---
layout: default
title: "Privacy & Permissions"
description: "Exactly what KeyPath accesses on your Mac, why, and what it does with your data"
theme: parchment
header_image: header-privacy.png
permalink: /guides/privacy/
---


# Privacy & Permissions

KeyPath needs deep access to your Mac to do its job. We know that's a lot to ask — especially from an app you just discovered. This page explains exactly what we access, why we can't do it with fewer permissions, and what we do (and don't do) with your data. No marketing spin — just the facts.

---

## The short version

- **No telemetry.** KeyPath collects no analytics, usage metrics, or crash reports. Zero.
- **Manual updates.** Download Update opens the official releases page in your browser. This build does not automatically check for or install updates.
- **Local keyboard data.** Rule and macro recording captures keys you choose to record, and the recent-keypress view keeps a limited history in memory. Diagnostic logs can include key names, including in release builds. KeyPath does not upload this keyboard data or these logs.
- **Open source.** Every claim on this page is verifiable in [the source code](https://github.com/malpern/KeyPath).
- **Everything stays on your Mac.** Configuration and logs are local files you own and control.

---

## How keyboard remapping works

To understand the permissions, it helps to see how keystrokes flow through the system:

```
  ┌──────────┐      ┌──────────────────────┐      ┌─────────┐
  │ Keyboard │ ───→ │   KeyPath session       │ ───→ │  Your   │
  │          │      │                       │      │  Apps    │
  │  You     │      │  1. Intercept key     │      │         │
  │  press   │      │  2. Apply your rules  │      │  App    │
  │  a key   │      │  3. Send remapped key │      │  sees   │
  │          │      │                       │      │  result │
  └──────────┘      └──────────────────────┘      └─────────┘
                            │
                    Keys are processed locally
                    and continue to your apps.
                    Diagnostic details may
                    appear in local logs.
```

The remapping engine sits between your keyboard and your apps, transforming keys according to your rules. Recording and recent-keypress views also use key events locally, and diagnostic logs can contain key names. Review logs before sharing them.

---

## Permissions in the driverless version

The driverless version uses **Accessibility** and **Input Monitoring**. The remapping runtime runs in your signed-in user session, without installing a virtual keyboard driver or a privileged remapping service.

### Accessibility

Allows KeyPath to intercept and send remapped keyboard events and support app-specific behavior. Setup guides you to the normal macOS consent screen.

### Input Monitoring

Allows keyboard input access required by the runtime. Setup checks effective access and guides you through the normal macOS grant when needed. Unknown status stays unverified until the runtime can report its access.

macOS may ask you to authenticate when changing these permissions. Removing a privileged installer does not remove macOS's own authentication requirements.

### No Full Disk Access or browser-history import

KeyPath no longer requests Full Disk Access or reads the protected macOS permission databases. It also no longer scans browser history or generates website suggestions from it. You can still enter website URLs manually and use existing saved launcher shortcuts.

Previously granted Full Disk Access is not automatically revoked by this change. You can remove KeyPath's old grant in System Settings if present.

### Secure Input boundary

Driverless remapping is unavailable in protected password-entry and Secure Input contexts. Normal password entry remains available through macOS; this version does not promise remapping in those contexts.

---

## Legacy installation locations

The following locations describe older system-service installations, not the driverless session runtime. They may remain on machines upgraded from an older release.

| What | Where | Contents |
|---|---|---|
| Your config | `~/.config/keypath/keypath.kbd` | Plain text — your key mappings and layer definitions |
| Service config | `/Library/LaunchDaemons/com.keypath.kanata.plist` | System service definition (root-owned) |
| Kanata binary | `/Library/KeyPath/bin/kanata` | The remapping engine binary |
| Logs | `/var/log/com.keypath.kanata.*.log` | Kanata startup messages, errors, reload events |

All files are local. Nothing is synced, uploaded, or shared.

---

## Network access

```
  ┌─────────────────────────────────────────────────┐
  │          KeyPath network connections             │
  │                                                  │
  │  ┌──────────┐                                    │
  │  │ KeyPath  │──→ GitHub (update check)  Optional │
  │  │          │                                    │
  │  │          │ ✗  No analytics servers            │
  │  │          │ ✗  No crash reporting              │
  │  │          │ ✗  No telemetry of any kind        │
  │  │          │ ✗  No cloud services               │
  │  └──────────┘                                    │
  │                                                  │
  │  Everything else is localhost or offline.         │
  └─────────────────────────────────────────────────┘
```

KeyPath makes **one** kind of network request:

### Update checks (Sparkle)

KeyPath uses the standard [Sparkle](https://sparkle-project.org/) framework to check for updates. This sends your app version and macOS version to GitHub to see if a newer version is available. Updates are cryptographically signed (EdDSA) so they can't be tampered with. You can disable update checks in Settings.

**That's it.** No analytics. No crash reporting. No telemetry. No tracking pixels. No cloud APIs. No Sentry, Firebase, Mixpanel, or any other third-party service.

---

## What about the Kanata TCP connection?

KeyPath communicates with the Kanata engine over a local TCP connection on `localhost:37001`. This is how it sends configuration reloads, layer switches, and receives status updates.

```
  ┌──────────────┐  localhost:37001  ┌──────────────┐
  │  KeyPath.app │ ←──────────────→  │    Kanata    │
  │  (your user) │    TCP (JSON)     │ (your user)  │
  └──────────────┘                   └──────────────┘
        │
        ├── "Reload config"
        ├── "Switch to layer X"
        └── "What's your status?"

  This connection NEVER leaves your Mac.
  It's 127.0.0.1 (localhost) only.
```

This connection is **localhost-only** — it never touches the network.

The connection does not use authentication, which is how Kanata's TCP server works upstream. In practice, this means any process on your Mac could send commands to Kanata. The risk is low — if malware has code execution on your Mac, it can already do far worse than remap your keys — but we mention it for completeness.

---

## Frequently asked questions

### Can KeyPath see my passwords?

The driverless runtime does not provide remapping in protected password-entry or Secure Input contexts. Do not rely on a remapped key for entering passwords.

### Does KeyPath work offline?

Yes, completely. The only optional network feature is update checks, which you can disable. Everything else works without a network connection.

### Is KeyPath open source?

Yes. [The full source code is on GitHub](https://github.com/malpern/KeyPath) under the MIT License. Every permission, every network request, and every file access described on this page is verifiable in the code.

### Can I use KeyPath without Full Disk Access?

Yes. KeyPath no longer requests or uses Full Disk Access. Browser-history import and direct permission-database inspection have been removed.

### How do I remove all KeyPath data?

Open KeyPath, choose **File > Uninstall KeyPath**, and confirm. This removes all system components, services, binaries, and configuration files.

### What about the VirtualHID driver?

The driverless version does not install or use the Karabiner VirtualHIDDevice driver. Existing driver installations belonging to other apps are separate.

### What about keyboard analytics or AI features?

Keyboard usage analytics are available in **Activity Insights**, a built-in plugin that ships with KeyPath. It tracks typing patterns and usage statistics locally on your Mac — nothing is sent anywhere. You can enable or disable it in Settings. KeyPath's core mission is keyboard remapping; Insights is an optional layer on top.

---

## Compare with alternatives

| | KeyPath | Karabiner-Elements | QMK Firmware |
|---|---|---|---|
| Sees all keystrokes | No — Secure Input boundary | Yes | Yes (on-keyboard) |
| Runs as root | No (driverless session) | Yes (event tap daemon) | N/A (firmware) |
| Telemetry | None | None | None |
| Open source | Yes (MIT) | Yes (Public Domain) | Yes (GPL) |
| Network access | Optional updates only | Optional updates | None |
| Keystroke logging | No | No | No |

---

## Still have concerns?

We take this seriously. If you have questions about KeyPath's privacy practices or find something in the source code that doesn't match what's described here, please [open an issue on GitHub](https://github.com/malpern/KeyPath/issues).

- **[FAQ](https://malpern.github.io/KeyPath/docs)** — More questions and answers about KeyPath
- **[Installation]({{ '/getting-started/installation/' | relative_url }})** — Setup wizard and permission walkthrough
- **[GitHub Issues](https://github.com/malpern/KeyPath/issues)** — Report bugs or ask questions
- **[Back to Docs](https://malpern.github.io/KeyPath/docs)**

## External references

- **[Karabiner-Elements](https://karabiner-elements.pqrs.org/)** — Alternative macOS keyboard remapper (for comparison) ↗
- **[Kanata](https://github.com/jtroo/kanata)** — The open-source remapping engine that powers KeyPath ↗
- **[kmonad](https://github.com/kmonad/kmonad)** — Another cross-platform keyboard remapper ↗
- **[Karabiner VirtualHIDDevice](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice)** — The virtual keyboard driver used by both KeyPath and Karabiner ↗
- **[Sparkle](https://sparkle-project.org/)** — The open-source update framework KeyPath uses ↗
- **[Apple TCC documentation](https://support.apple.com/guide/security/controlling-app-access-to-files-secddd1d86a6/web)** — How macOS manages app permissions ↗
