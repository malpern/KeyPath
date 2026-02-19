
# Privacy & Permissions

KeyPath needs deep access to your Mac to do its job. We know that's a lot to ask — especially from an app you just discovered. This page explains exactly what we access, why we can't do it with fewer permissions, and what we do (and don't do) with your data. No marketing spin — just the facts.

---

## The short version

- **No telemetry.** KeyPath collects no analytics, usage metrics, or crash reports. Zero.
- **No phoning home.** The only network request KeyPath makes is checking for updates. You can disable that too.
- **No logging.** KeyPath does not record, store, or transmit your keystrokes.
- **Open source.** Every claim on this page is verifiable in [the source code](https://github.com/malpern/KeyPath).
- **Everything stays on your Mac.** Configuration and logs are local files you own and control.

---

## How keyboard remapping works

To understand the permissions, it helps to see how keystrokes flow through the system:

```
  ┌──────────┐      ┌──────────────────────┐      ┌─────────┐
  │ Keyboard │ ───→ │   Kanata (root)       │ ───→ │  Your   │
  │          │      │                       │      │  Apps    │
  │  You     │      │  1. Intercept key     │      │         │
  │  press   │      │  2. Apply your rules  │      │  App    │
  │  a key   │      │  3. Send remapped key │      │  sees   │
  │          │      │                       │      │  result │
  └──────────┘      └──────────────────────┘      └─────────┘
                            │
                    Nothing is recorded,
                    stored, or sent anywhere.
                    Keys pass through and
                    continue to your apps.
```

The remapping engine sits between your keyboard and your apps. It has to — that's how remapping works. The important thing is what happens to your keystrokes: they get transformed and passed along. Nothing else.

---

## Why so many permissions?

We get it. The first time you install KeyPath, macOS asks you to grant several permissions and enter your admin password. That feels like a lot for a keyboard app.

The honest answer: **keyboard remapping is a system-level operation.** Remapping happens *before* keystrokes reach your apps, which means intercepting them at a low level. Every keyboard remapping tool — Karabiner-Elements, QMK, kmonad, Kanata standalone — requires the same kind of access. If a tool claims to remap keys without these permissions, it's either not doing system-wide remapping or it's not telling you the full story.

```
  ┌─────────────────────────────────────────────────┐
  │              Permissions Overview                │
  │                                                  │
  │  Input Monitoring ·········· Read keystrokes     │
  │  Accessibility ············· Send remapped keys  │
  │  Full Disk Access (opt) ···· Check permissions   │
  │  Admin password (once) ····· Install service     │
  │                                                  │
  │  ◆ Required    ◇ Optional                        │
  │  ◆ Input Monitoring                              │
  │  ◆ Accessibility                                 │
  │  ◇ Full Disk Access                              │
  └─────────────────────────────────────────────────┘
```

Here's what each one does.

### Input Monitoring

**What it does:** Lets Kanata (the remapping engine) see your keystrokes before they reach applications.

**Why it's needed:** This is the core of keyboard remapping. To turn a tap on `F` into the letter "f" and a hold on `F` into the Command key, something has to intercept that keystroke before macOS processes it.

**What this means in practice:** Yes, the remapping engine can technically see everything you type — passwords, messages, everything. This is true of *every* keyboard remapping tool. It's also true of your keyboard's own firmware. KeyPath doesn't record, transmit, or store your keystrokes. They flow through the remapping engine, get transformed, and continue to your apps. That's it.

### Accessibility

**What it does:** Lets KeyPath send the remapped keystrokes back to your apps, and detect which app is currently active (for app-specific keymaps).

**Why it's needed:** Input Monitoring lets KeyPath *read* keystrokes. Accessibility lets it *write* the remapped ones back. Without this, intercepted keys would just disappear.

```
  Input Monitoring          Accessibility
  ┌───────────┐             ┌───────────┐
  │  READ     │             │  WRITE    │
  │           │             │           │
  │ Intercept │             │ Send the  │
  │ what you  │     ───→    │ remapped  │
  │ pressed   │             │ key to    │
  │           │             │ your apps │
  └───────────┘             └───────────┘

  Both needed. One without the other is useless.
```

KeyPath also uses Accessibility to detect app switches for features like app-specific keyboard layouts.

### Full Disk Access (optional)

**What it does:** Lets KeyPath read macOS's permission database to check whether Kanata has been granted the permissions it needs.

**Why it's needed:** There's a chicken-and-egg problem: KeyPath needs to verify Kanata's permissions *before* starting it, but the only way to check another process's permissions is to read Apple's TCC database, which requires Full Disk Access.

```
  Without Full Disk Access:       With Full Disk Access:

  KeyPath: "Does Kanata have      KeyPath reads TCC database:
  Input Monitoring?"              "Kanata has Input Monitoring ✓
                                   Kanata needs Accessibility ✗"
  macOS:  "¯\_(ツ)_/¯"                    │
          (can't check other              ↓
           apps' permissions)     Guides you step by step
```

**If you skip this:** KeyPath still works. You'll just need to grant permissions to Kanata manually in System Settings, and KeyPath won't be able to show you accurate permission status in its setup wizard. It's a convenience feature, not a requirement.

**What KeyPath reads:** Only permission grant records (which apps have which permissions). It's read-only — KeyPath cannot modify permissions.

### Administrator password (one-time)

**What it does:** Installs a privileged helper and a LaunchDaemon that runs Kanata as a system service.

**Why it's needed:** Keyboard remapping requires root-level access to intercept hardware input events. The helper installs the Kanata binary, manages the system service, and handles the virtual keyboard driver. All operations are pre-defined in code — the helper cannot run arbitrary commands.

```
  ┌─────────────────────────────────────────────────┐
  │                What runs where                   │
  │                                                  │
  │  Your account (normal user):                     │
  │  ┌────────────────────────┐                      │
  │  │  KeyPath.app           │  The UI you interact │
  │  │  (SwiftUI interface)   │  with. No root.      │
  │  └────────────────────────┘                      │
  │            │ TCP localhost                        │
  │            ↓                                     │
  │  Root (system service):                          │
  │  ┌────────────────────────┐                      │
  │  │  Kanata                │  The remapping       │
  │  │  (LaunchDaemon)        │  engine. Root        │
  │  └────────────────────────┘  required for HID.   │
  └─────────────────────────────────────────────────┘
```

**What runs as root:** Only the Kanata remapping engine and the installer helper. The KeyPath app itself runs as your normal user account.

---

## What KeyPath stores on your Mac

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
  │  (your user) │    TCP (JSON)     │    (root)    │
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

The remapping engine sees all keystrokes, including passwords, but only to transform them. KeyPath doesn't record, store, or transmit what you type. This is the same access model as Karabiner-Elements, QMK firmware, and every other keyboard remapping tool.

### Does KeyPath work offline?

Yes, completely. The only optional network feature is update checks, which you can disable. Everything else works without a network connection.

### Is KeyPath open source?

Yes. [The full source code is on GitHub](https://github.com/malpern/KeyPath) under the MIT License. Every permission, every network request, and every file access described on this page is verifiable in the code.

### Can I use KeyPath without Full Disk Access?

Yes. Full Disk Access is optional — it just makes the setup wizard smoother. Without it, you grant permissions directly to Kanata in System Settings and KeyPath works normally.

### How do I remove all KeyPath data?

Open KeyPath, choose **File > Uninstall KeyPath**, and confirm. This removes all system components, services, binaries, and configuration files.

### What about the VirtualHID driver?

KeyPath installs the [Karabiner VirtualHIDDevice driver](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice) to create a virtual keyboard for sending remapped keystrokes. This is a well-established open-source driver also used by Karabiner-Elements. It requires system approval on first install and can be removed via KeyPath's uninstaller.

### What about keyboard analytics or AI features?

Keyboard usage analytics and AI-assisted configuration are available in **KeyPath Insights**, a separate companion app. They are not part of KeyPath itself. KeyPath remaps your keyboard — that's the whole app.

---

## Compare with alternatives

| | KeyPath | Karabiner-Elements | QMK Firmware |
|---|---|---|---|
| Sees all keystrokes | Yes (required) | Yes | Yes (on-keyboard) |
| Runs as root | Yes (Kanata engine) | Yes (event tap daemon) | N/A (firmware) |
| Telemetry | None | None | None |
| Open source | Yes (MIT) | Yes (Public Domain) | Yes (GPL) |
| Network access | Optional updates only | Optional updates | None |
| Keystroke logging | No | No | No |

---

## Still have concerns?

We take this seriously. If you have questions about KeyPath's privacy practices or find something in the source code that doesn't match what's described here, please [open an issue on GitHub](https://github.com/malpern/KeyPath/issues).

- **[FAQ](https://keypath-app.com/faq)** — More questions and answers about KeyPath
- **[Installation](https://keypath-app.com/getting-started/installation)** — Setup wizard and permission walkthrough
- **[Debugging Guide](help:debugging)** — Troubleshooting permission issues
- **[Back to Docs](https://keypath-app.com/docs)**

## External references

- **[Karabiner-Elements](https://karabiner-elements.pqrs.org/)** — Alternative macOS keyboard remapper (for comparison) ↗
- **[Kanata](https://github.com/jtroo/kanata)** — The open-source remapping engine that powers KeyPath ↗
- **[kmonad](https://github.com/kmonad/kmonad)** — Another cross-platform keyboard remapper ↗
- **[Karabiner VirtualHIDDevice](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice)** — The virtual keyboard driver used by both KeyPath and Karabiner ↗
- **[Sparkle](https://sparkle-project.org/)** — The open-source update framework KeyPath uses ↗
- **[Apple TCC documentation](https://support.apple.com/guide/security/controlling-app-access-to-files-secddd1d86a6/web)** — How macOS manages app permissions ↗
