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

- **No transmitted telemetry.** KeyPath does not upload analytics, usage metrics, or crash reports. Optional Activity Insights keeps keyboard usage statistics locally.
- **App updates.** Once a day KeyPath asks GitHub whether a new version exists, and by default installs it when you quit. The request carries no keyboard data or system profile. Turn either off in **Settings → General → Updates**.
- **Offline Help.** Guides, styles and images are included in the app. Opening a guide can quietly check GitHub Pages for compatible Help content updates; no keyboard data or logs are sent.
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

The driverless version asks for one permission: **Device Control and Data Access** (called **Accessibility** before macOS 27). The remapping runtime runs in your signed-in user session, without installing a virtual keyboard driver or a privileged remapping service.

### Device Control and Data Access

Allows KeyPath to intercept and send remapped keyboard events and support app-specific behavior. Setup guides you to the normal macOS consent screen.

### Effective keyboard access

KeyPath verifies that its running process can receive and post keyboard events. Device Control and Data Access supplies this access; KeyPath asks for no other privacy permission. Setup checks actual runtime access rather than treating a Settings toggle as proof of readiness. If the toggle is on but remapping still lacks access, quit and reopen KeyPath.

macOS may ask you to authenticate when changing these permissions. Removing a privileged installer does not remove macOS's own authentication requirements.

### No Full Disk Access or browser-history import

KeyPath no longer requests Full Disk Access or reads the protected macOS permission databases. It also no longer scans browser history or generates website suggestions from it. You can still enter website URLs manually and use existing saved launcher shortcuts.

Previously granted Full Disk Access is not automatically revoked by this change. You can remove KeyPath's old grant in System Settings if present.

### Secure Input boundary

Driverless remapping is unavailable in protected password-entry and Secure Input contexts. Normal password entry remains available through macOS; this version does not promise remapping in those contexts.

---

## Where your data lives

| What | Where | Contents |
|---|---|---|
| Your config | `~/.config/keypath/keypath.kbd` | Plain text — your key mappings and layer definitions |
| App data | `~/Library/Application Support/KeyPath/` | Activity Insights statistics (if you turn it on) and app state |
| Caches | `~/Library/Caches/com.keypath.KeyPath/` | Temporary app data |
| App logs | `~/Library/Logs/KeyPath/` | Local diagnostic logs |

---

## Legacy installation locations

KeyPath 1.0.1 and earlier installed a root-owned system service. Current versions do not install or use the service, the engine, or the logs listed here, but these files may remain on Macs upgraded from those releases.

| What | Where | Contents |
|---|---|---|
| Service config | `/Library/LaunchDaemons/com.keypath.kanata.plist` | System service definition (root-owned) |
| Kanata binary | `/Library/KeyPath/bin/kanata` | The remapping engine binary |
| Logs | `/var/log/com.keypath.kanata.*.log` | Kanata startup messages, errors, reload events |

All files are local. Nothing is synced, uploaded, or shared.

---

## Network access

### Offline Help updates

Help opens a saved local copy immediately, including on a first launch without
internet. When you open an article, KeyPath can check the public Help feed at
`malpern.github.io/KeyPath/offline-help/` and download changed guides, images and
styles in the background. These are ordinary HTTPS downloads; they do not upload
your rules, keystrokes, recordings or logs. The server receives standard web
request information, such as your IP address.

Only a complete compatible content update replaces the local copy. If the network
or download fails, the previous copy remains available. External website links
still need internet access. Help content updates do not install a new app or run
scripts.

### App updates

KeyPath uses [Sparkle](https://sparkle-project.org/) to check for new versions once a day. It fetches a list of releases from GitHub over HTTPS; the request carries no keyboard data, and Sparkle's system profiling is off. Each update is checked against KeyPath's signing key and Developer ID before it is installed. By default an update installs when you quit KeyPath, after your keyboard is released, and your rules are kept. In **Settings → General → Updates** you can turn off automatic checks or automatic installation, or check by hand.

Keyboard diagnostics and optional Activity Insights stay local; KeyPath does not upload analytics, usage metrics, crash reports or keyboard logs.

---

## What about the Kanata TCP connection?

KeyPath communicates with the Kanata engine over a local TCP connection on `localhost:37001`. This is how it sends configuration reloads and layer switches, and receives key and layer events.

```
  ┌──────────────┐  localhost:37001  ┌──────────────┐
  │  KeyPath.app │ ←──────────────→  │    Kanata    │
  │  (your user) │    TCP (JSON)     │ (your user)  │
  └──────────────┘                   └──────────────┘
        │
        ├── "Reload config"
        ├── "Switch to layer X"
        └── Receive key and layer events

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

Keyboard remapping, recording, local diagnostics and the bundled Help guides work offline. Help can quietly download compatible content updates when connected. Update checks and external links need internet access; without it, KeyPath simply finds no update.

### Is KeyPath open source?

Yes. [The full source code is on GitHub](https://github.com/malpern/KeyPath) under the MIT License. Every permission, every network request, and every file access described on this page is verifiable in the code.

### Can I use KeyPath without Full Disk Access?

Yes. KeyPath no longer requests or uses Full Disk Access. Browser-history import and direct permission-database inspection have been removed.

### How do I remove the driverless app and saved rules?

Use **Settings → Repair/Remove → Uninstall KeyPath**. KeyPath saves a backup in Downloads, removes your rules and preferences, disables launch at login, and moves the app to the Trash. Local diagnostic logs remain in `~/Library/Logs/KeyPath/`. Moving only the app to the Trash leaves settings behind. Uninstall does not revoke macOS permission grants or remove drivers installed by other apps.

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
| Telemetry | No uploads; optional local Insights | None | None |
| Open source | Yes (MIT) | Yes (Public Domain) | Yes (GPL) |
| Network access | Help content refresh; daily update check (can be turned off) | Optional updates | None |
| Keystroke logging | Key names can appear in local diagnostics | No | No |

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
- **[Karabiner VirtualHIDDevice](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice)** — The virtual keyboard driver used by legacy KeyPath installations and Karabiner ↗
- **[Sparkle](https://sparkle-project.org/)** — The update framework KeyPath uses ↗
- **[Apple TCC documentation](https://support.apple.com/guide/security/controlling-app-access-to-files-secddd1d86a6/web)** — How macOS manages app permissions ↗
