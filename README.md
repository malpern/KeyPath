# KeyPath

<div align="center">

  <a href="https://keypath-app.com">
    <img src="https://malpern.github.io/KeyPath/images/keypath-hero-nobg.png" alt="KeyPath — Keys that do more" width="800"/>
  </a>

  ### Keys that do more.

  Remap keys, launch apps, tile windows, and automate workflows — all without leaving the home row.

  <a href="https://keypath-app.com"><strong>keypath-app.com</strong></a> · <a href="https://github.com/malpern/KeyPath/releases">Download</a> · <a href="https://malpern.github.io/KeyPath/documentation/">Docs</a> · <a href="https://github.com/malpern/KeyPath/issues">Issues</a>

  [![macOS 15+](https://img.shields.io/badge/macOS-15%2B-blue.svg)](https://www.apple.com/macos/)
  [![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
  [![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

</div>

---

## What is KeyPath?

KeyPath is a native macOS app that gives you complete control over your keyboard. It's powered by [Kanata](https://github.com/jtroo/kanata), a cross-platform remapping engine — but you never need to touch a config file or the command line.

- **Record a remap in seconds** — click record, press input key, press output key, save. Done.
- **Changes apply instantly** — no restart, no logout, no manual service management.
- **Works at the system level** — remappings are active everywhere, including the login screen.

---

## What you can do

| Capability | What it means for you |
|---|---|
| **Basic remapping** | Swap any key for any other key. Caps Lock → Escape is one click. |
| **Home row mods** | Tap A/S/D/F for letters, hold them for Ctrl/Alt/Cmd/Shift. Your fingers never leave home row. |
| **Tap-hold** | One key, two purposes. Tap Space for space, hold it for a layer switch. |
| **Tap-dance** | Different actions based on how many times you tap — single, double, triple. |
| **Layers** | Stack keyboard layouts like transparent sheets. Switch instantly between navigation, symbols, numbers, and more. |
| **Vim navigation** | HJKL as arrow keys. Navigate text, code, and apps without reaching for the arrow cluster. |
| **Macros** | Chain multiple keystrokes into a single key. Save-close-quit with one press. |
| **App launching** | Bind any key or chord to open apps, URLs, files, or scripts. |
| **Window tiling** | Snap windows to halves, quarters, or fullscreen — no mouse needed. |
| **Chords & sequences** | Press keys simultaneously or in order to trigger actions. |

### Pre-built rules included

Don't want to build from scratch? KeyPath ships with ready-to-use rule collections:

- Caps Lock remap (Escape on tap, Hyper on hold)
- Home row mods
- Vim navigation layer
- Window snapping
- Quick launcher
- Symbol layer

Enable any of them with a single toggle.

---

## Works with your keyboard

**Layouts:** QWERTY, Colemak, Colemak-DH, Dvorak, Workman, Graphite, AZERTY, QWERTZ, JIS, and more.

**Keyboards:** MacBook built-in, 60%, 65%, 75%, TKL, full-size, Corne, Ferris Sweep, Kinesis Advantage.

KeyPath's live keyboard overlay shows your active mappings on a visual representation of your actual keyboard.

---

## Already using Kanata?

Keep your config. Keep your workflow. Just add a native Mac app on top.

- **Zero migration** — KeyPath auto-imports your existing `kanata.kbd`
- **Edit anywhere** — changes hot-reload instantly via TCP
- **One line added** — `(include keypath-apps.kbd)` enables app integration features

Copy your config to `~/.config/keypath/keypath.kbd` and run the setup wizard.

---

## How it works

### Setup (once)

1. **Download** KeyPath from the [releases page](https://github.com/malpern/KeyPath/releases) or [build from source](#build-from-source)
2. **Run the setup wizard** — it handles permissions, drivers, and services automatically
3. **Start remapping** — create rules visually or enable pre-built collections

### Under the hood

KeyPath installs a system-level LaunchDaemon that runs Kanata reliably in the background. The app communicates with it over localhost TCP for instant config reloads. You get:

- Automatic driver installation (Karabiner VirtualHID)
- Guided permission setup (Input Monitoring + Accessibility)
- Crash recovery and health monitoring
- Conflict detection with other keyboard tools
- Emergency stop (**Ctrl + Space + Esc**) if anything goes wrong

---

## Safety

- **Emergency stop** — Press **Ctrl + Space + Esc** to instantly disable all remappings
- **No internet required** — works completely offline
- **No telemetry** — zero data collection
- **No kernel extensions** — uses Apple's modern driver framework
- **Signed and notarized** — passes all macOS security checks

---

## Build from source

```bash
git clone https://github.com/malpern/KeyPath.git
cd KeyPath
./build.sh                         # Full build: compile, sign, notarize, deploy
```

Shortcuts:
- `SKIP_NOTARIZE=1 ./build.sh` — skip notarization for faster local builds
- `./Scripts/quick-deploy.sh` — incremental rebuild (run `./build.sh` once first)

### Community builds (no Apple credentials needed)

```bash
swift build
swift test
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for full contributor setup.

---

## Requirements

- **macOS 15.0 (Sequoia)** or later
- **Apple Silicon or Intel**

Dependencies (Kanata engine + Karabiner VirtualHID driver) are bundled and installed automatically.

---

## Uninstall

**From the app:** File → Uninstall KeyPath — removes all services, helpers, and the app.

**From the command line:**
```bash
sudo ./Scripts/uninstall.sh
```

---

## Documentation

- [Architecture overview](https://malpern.github.io/KeyPath/architecture/)
- [Tap-hold & tap-dance guide](docs/TAP_HOLD_TAP_DANCE.md)
- [FAQ](docs/FAQ.md)
- [Debugging guide](docs/DEBUGGING_KANATA.md)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)
- [Changelog](CHANGELOG.md)

---

## Acknowledgments

- [Kanata](https://github.com/jtroo/kanata) — the keyboard remapping engine that powers KeyPath
- [Karabiner-Elements](https://karabiner-elements.pqrs.org/) — VirtualHID driver and architectural inspiration

---

<div align="center">
  <p>Made by <a href="https://github.com/malpern">Micah Alpern</a> for the macOS and mechanical keyboard communities.</p>
  <p>If KeyPath helps you, consider starring the repo.</p>
</div>
