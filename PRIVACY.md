# Privacy Policy

**Last Updated:** November 2026

This document explains what data KeyPath accesses, stores and transmits. It
describes current builds, which run the remapping engine in your signed-in user
session. KeyPath 1.0.1 and earlier worked differently; see
[Earlier versions](#earlier-versions).

The user-facing version of this page, with diagrams, is
[Privacy & Permissions](https://malpern.github.io/KeyPath/guides/privacy/).

## Summary

- **No analytics, telemetry or crash reporting.** KeyPath contains no tracking
  SDKs and uploads no usage data.
- **Keyboard data stays on your Mac.** Key events are processed locally for
  remapping. KeyPath does not log the keys you press. Diagnostic logs can name
  keys from your mappings; nothing uploads them.
- **One permission.** Accessibility (shown as **Device Control and Data
  Access** on macOS 27). No Input Monitoring, no Full Disk Access.
- **No root.** KeyPath does not install a privileged helper, a system service
  or a keyboard driver.

---

## Data KeyPath Accesses

### Keyboard Input

KeyPath needs **Accessibility** permission to read and remap keys.

**What happens to your keystrokes:**
- Key events are read by the Kanata engine, which KeyPath runs as an ordinary
  process in your user session
- Keys are remapped according to your configuration and passed on to your apps
- No keystroke data is transmitted over the network
- Remapping does not run in password fields and other Secure Input contexts,
  or at the login screen

**Where key names can appear on disk:**
- Diagnostic logs in `~/Library/Logs/KeyPath/` do not record the keys you
  press, including while you record a shortcut, at any log level. (This is the
  app you download; a developer's own debug build does log them.) They can name
  keys from your mappings, or keys you click in the keyboard view. Review a log
  before sharing it.
- If you turn on Activity Insights, usage statistics (shortcuts used, app
  switches, actions) are stored encrypted. It does not store typed text.

**Recent keypress view:**
- Shows up to 100 recent key events, held in memory only
- Cleared when the app closes

### Browser History

KeyPath does not read browser history. The earlier Quick Launch suggestion
feature that did so has been removed.

---

## Data KeyPath Stores

| Location | Contents |
|----------|----------|
| `~/.config/keypath/keypath.kbd` | Your keyboard remapping configuration |
| `~/.config/keypath/keypath-apps.kbd` | KeyPath-generated companion config (included by `keypath.kbd`) |
| `~/.config/keypath/RuleCollections.json` | Which rule collections are on |
| `~/.config/keypath/CustomRules.json` | Custom rules you create in the app |
| `~/.config/keypath/AppKeymaps.json` | Per-app keymaps (if configured) |
| `~/Library/Application Support/KeyPath/` | App state, cached website icons, plugins, and encrypted Activity Insights data if you turn it on |
| `~/Library/Caches/com.keypath.KeyPath/` | Temporary app data |
| `~/Library/Logs/KeyPath/keypath-debug.log` | Diagnostic logs (rotated at 5 MB, 3 files kept) |

### Preferences

Standard macOS preferences (`UserDefaults`) store app settings such as window
positions and feature toggles.

### Secure Storage (Keychain)

- If you add a Claude API key for the optional AI config repair feature, it is
  stored in the macOS Keychain.
- The encryption key for Activity Insights data is stored in the Keychain with
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` protection.

---

## Network Connections

KeyPath makes these network requests. None of them send keystrokes, rules,
recordings or logs.

### 1. Help content

**Destination:** `https://malpern.github.io/KeyPath/offline-help/`

Help guides ship inside the app. Opening a guide can check for updated guides,
images and styles and download them in the background.

### 2. App updates

Current builds do not check for or install updates automatically. **Download
Update** opens the GitHub releases page in your browser.

### 3. QMK keyboard database

**Destination:** `https://keyboards.qmk.fm` and `https://raw.githubusercontent.com`

Fetches keyboard layout definitions when you use the QMK keyboard import
feature. Popular keyboards are bundled with the app and need no network.

### 4. Website icons

**Destination:** the website's own domain, or Google's favicon service
(`https://www.google.com/s2/favicons`)

When you create a mapping that opens a website, KeyPath downloads that site's
icon. Depending on where the icon is shown, the request goes to the site
itself or to Google's favicon service, which receives the site's domain name.
Icons are cached locally.

### 5. Plugins

**Destination:** `https://github.com/malpern-labs/KeyPath/releases`

Activity Insights ships inside the app. If a plugin is not present, KeyPath
can download it from the project's GitHub releases when you choose to install
it.

### 6. AI config repair (optional)

**Destination:** `https://api.anthropic.com`

Used only if you add your own Claude API key. KeyPath contacts Anthropic to
check the key, and, when you ask it to repair a configuration error, sends:

- your keyboard configuration file
- the validation error

It does not send keystrokes, logs, system information or data from other apps.

---

## Scripts You Choose to Run

Script actions are off by default. If you turn them on and bind a key to a
script, that script runs with your user account's normal access, including
the network. KeyPath asks before running a script the first time. What a
script does is up to the script; see
[Script execution](https://malpern.github.io/KeyPath/guides/script-execution/).

---

## The Local Engine Connection

KeyPath talks to the Kanata engine over a Unix-domain socket in a folder only
your account can open. The connection never leaves your Mac.

Only the KeyPath app that started the engine can connect: on every
connection the engine checks the other process's user, process ID and process
ID version, which macOS reports for the socket itself, and that its running
code is signed as KeyPath. Other programs, other
users on the Mac and sandboxed apps are refused before they receive any key
event ([ADR-046](docs/adr/adr-046-session-engine-control-channel.md)).

Earlier builds used an unauthenticated port on `127.0.0.1:37001`. It is gone.

---

## Permissions Explained

| Permission | Why It's Needed |
|------------|-----------------|
| **Accessibility** (Device Control and Data Access on macOS 27) | Reading and remapping keys, and app-specific behaviour |
| **Automation** (only if prompted) | Actions you configure that control other apps, such as AppleScript actions |

KeyPath does not request Input Monitoring or Full Disk Access, and does not
read macOS's permission databases.

---

## What KeyPath Does NOT Do

- **No uploaded keystrokes** — key events are never transmitted
- **No analytics** — no Firebase, Mixpanel, Amplitude or similar SDKs
- **No crash reporting** — no Sentry, Crashlytics or automatic error reporting
- **No clipboard monitoring**
- **No browser history access**
- **No root-level components** — no privileged helper, LaunchDaemon or driver

---

## Third-Party Components

### Kanata

KeyPath uses [Kanata](https://github.com/jtroo/kanata) as its remapping
engine. It runs locally in your user session and makes no network connections.
KeyPath's build of Kanata cannot run shell commands from a configuration file.

### Sparkle

KeyPath uses the [Sparkle](https://sparkle-project.org/) update framework to
check GitHub for new versions once a day and, by default, install them on Quit.
Updates must carry KeyPath's EdDSA signature and Developer ID. System profiling
is disabled, so the check sends no information about your Mac. Both automatic
checks and automatic installation can be turned off in Settings → General →
Updates.

---

## Your Control

- **Turn off the recent keypress view** in the app
- **Leave Activity Insights off** — it is off until you enable it
- **Leave AI features off** — don't add a Claude API key
- **Delete your data** — **Settings → Repair/Remove → Uninstall KeyPath**
  saves a backup to Downloads, removes your rules and preferences, and moves
  the app to the Trash. Diagnostic logs remain in `~/Library/Logs/KeyPath/`
  until you delete them. Uninstalling does not revoke the Accessibility grant;
  remove it in System Settings. The command-line tool's link in
  `~/.local/bin` is removed too. A copy installed by a version before
  November 2026 at `/usr/local/bin/keypath-cli` stays; remove it with
  `sudo rm /usr/local/bin/keypath-cli`.

---

## Data Retention

- **Recent keypress view:** memory only, cleared when the app closes
- **Website icon cache:** kept until cleared or the app is uninstalled
- **Diagnostic logs:** rotated automatically, 3 files of up to 5 MB each
- **Activity Insights data:** kept until you turn the feature off and delete it
- **Configuration:** kept until you delete it

---

## Earlier versions

KeyPath 1.0.1 and earlier installed a root-owned system service and the
Karabiner VirtualHID driver, and asked for Input Monitoring and, optionally,
Full Disk Access. Current builds use none of these. Files from those versions
may remain on a Mac that was upgraded:

| Location | Contents |
|----------|----------|
| `/Library/LaunchDaemons/com.keypath.kanata.plist` | System service definition |
| `/Library/KeyPath/bin/kanata` | The remapping engine binary |
| `/var/log/com.keypath.kanata.*.log` | Service logs |

Current builds do not remove these files. To remove them yourself, run in
Terminal (each asks for an administrator password):

```bash
sudo launchctl bootout system/com.keypath.kanata
sudo rm -f /Library/LaunchDaemons/com.keypath.kanata.plist
sudo rm -f /Library/KeyPath/bin/kanata
sudo rmdir /Library/KeyPath/bin /Library/KeyPath
sudo rm -f /var/log/com.keypath.kanata.*.log
```

The first command reports an error if the service is not running, and
`rmdir` refuses if a folder still holds other files; both are fine.

A Full Disk Access or Input Monitoring grant made for an earlier version is
not revoked automatically. You can remove it in System Settings.

---

## Open Source

KeyPath is open source. You can audit the code yourself:

- **Repository:** [github.com/malpern-labs/KeyPath](https://github.com/malpern-labs/KeyPath)
- **License:** MIT

---

## Contact

- **Security issues:** see [SECURITY.md](SECURITY.md); do not open a public issue
- **GitHub Issues:** [github.com/malpern-labs/KeyPath/issues](https://github.com/malpern-labs/KeyPath/issues)
- **Discussions:** [github.com/malpern-labs/KeyPath/discussions](https://github.com/malpern-labs/KeyPath/discussions)

---

## Changes to This Policy

This policy is updated as features change. Significant changes are noted in
release notes. The "Last Updated" date at the top shows the latest revision.
