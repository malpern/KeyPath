# Privacy Policy

**Last Updated:** December 2024

KeyPath is designed with privacy as a core principle. This document explains exactly what data KeyPath accesses, stores, and transmits.

## Summary

- **No analytics or telemetry** — KeyPath contains no tracking SDKs
- **No crash reporting** — Errors are logged locally only
- **No keystroke logging** — Key events are processed for remapping, not recorded
- **Local-first design** — Your configuration and data stay on your Mac

---

## Data KeyPath Accesses

### Keyboard Input

KeyPath requires **Input Monitoring** permission to function as a keyboard remapper. This is a macOS system requirement for any app that modifies keyboard behavior.

**What happens to your keystrokes:**
- Keystrokes are intercepted by the Kanata engine running as a system service
- Keys are remapped according to your configuration and passed to the system
- No keystroke data is transmitted over the network
- No keystroke logs are saved to disk

**Visual keyboard display:**
- The live keyboard visualization shows recent keypresses (up to 100 events in memory)
- This feature can be toggled on/off
- Data is cleared when the app closes

### Browser History (Optional)

If you enable the **Quick Launch** feature to suggest frequently visited websites, KeyPath can scan your browser history.

**This feature:**
- Requires you to grant **Full Disk Access** permission
- Reads only domain names and visit counts (not full URLs or page content)
- Processes data locally in temporary files that are deleted after analysis
- Never transmits browser history over the network

**Supported browsers:** Safari, Chrome, Firefox, Arc, Brave, Edge, Dia

---

## Data KeyPath Stores

### Configuration Files

| Location | Contents |
|----------|----------|
| `~/Library/Application Support/KeyPath/keypath.kbd` | Your keyboard remapping configuration |
| `~/Library/Application Support/KeyPath/Favicons/` | Cached website icons for Quick Launch |
| `~/Library/Logs/KeyPath/keypath-debug.log` | Debug logs (rotated at 5MB, max 3 files) |

### Preferences

Standard macOS preferences (`UserDefaults`) store app settings like window positions and communication protocol choices. No sensitive data is stored in preferences.

### Secure Storage (Keychain)

If you use the optional AI config repair feature, your Claude API key is stored in the macOS Keychain with:
- Encryption at rest
- Access limited to KeyPath only
- `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` protection

---

## Network Connections

KeyPath makes the following network requests:

### 1. Update Checks

**Destination:** `https://raw.githubusercontent.com/malpern/KeyPath/master/appcast.xml`

- Checks for app updates via the Sparkle framework
- **System profiling is disabled** — no hardware or software information is sent
- Frequency: Once per day (configurable)

### 2. QMK Keyboard Database

**Destination:** `https://api.github.com` and `https://raw.githubusercontent.com`

- Fetches keyboard layout definitions for the QMK keyboard import feature
- Cached locally for 1 hour to minimize requests
- Popular keyboards are bundled with the app (no network needed)

### 3. Website Favicons

**Destination:** User-specified domains

- Downloads favicon.ico files for Quick Launch website icons
- Only fetches from domains you've added
- Cached locally to avoid repeated requests

### 4. AI Config Repair (Optional, User-Initiated)

**Destination:** `https://api.anthropic.com/v1/messages`

This feature is **entirely optional** and only activates when:
1. You provide your own Claude API key
2. You explicitly click to repair a configuration error

**What is sent:**
- Your keyboard configuration file
- The specific validation error
- Key mapping context

**What is NOT sent:**
- Keystroke logs
- Browser history
- System information
- Any data from other applications

---

## Permissions Explained

| Permission | Why It's Needed |
|------------|-----------------|
| **Input Monitoring** | Required by macOS for any keyboard remapping |
| **Accessibility** | Required by macOS for system-level key event handling |
| **Full Disk Access** | Only if you enable browser history scanning for Quick Launch |
| **Network** | Update checks, keyboard database, favicon fetching |

---

## What KeyPath Does NOT Do

- **No keylogging** — Keystrokes are not recorded or transmitted
- **No analytics** — No Firebase, Mixpanel, Amplitude, or similar SDKs
- **No crash reporting** — No Sentry, Crashlytics, or automatic error reporting
- **No system profiling** — Sparkle's system profiling is explicitly disabled
- **No clipboard monitoring** — KeyPath does not access your clipboard
- **No background data collection** — No hidden telemetry or tracking

---

## Third-Party Components

### Kanata

KeyPath uses [Kanata](https://github.com/jtroo/kanata) as its keyboard remapping engine. Kanata runs locally as a system service and does not make any network connections.

### Sparkle

KeyPath uses the [Sparkle](https://sparkle-project.org/) framework for update checking. Sparkle is configured with:
- `SUEnableSystemProfiling = false` (no system information sent)
- EdDSA signature verification (updates are cryptographically signed)

---

## Your Control

You have full control over KeyPath's behavior:

- **Disable keypress visualization** — Toggle off in the app
- **Skip browser history scanning** — Don't grant Full Disk Access
- **Disable AI features** — Don't provide a Claude API key
- **Disable auto-updates** — Configure in app preferences
- **Delete all data** — Uninstall removes all local data

---

## Data Retention

- **Keypress visualization:** Cleared when app closes (memory only)
- **Browser history scan results:** Deleted immediately after processing
- **Favicon cache:** Persists until manually cleared or app uninstalled
- **Debug logs:** Automatically rotated, max 15MB total
- **Configuration:** Persists until you delete it

---

## Open Source

KeyPath is open source. You can audit the code yourself:

- **Repository:** [github.com/malpern/KeyPath](https://github.com/malpern/KeyPath)
- **License:** MIT

---

## Contact

If you have privacy questions or concerns:

- **GitHub Issues:** [github.com/malpern/KeyPath/issues](https://github.com/malpern/KeyPath/issues)
- **Discussions:** [github.com/malpern/KeyPath/discussions](https://github.com/malpern/KeyPath/discussions)

---

## Changes to This Policy

This privacy policy may be updated as features change. Significant changes will be noted in release notes. The "Last Updated" date at the top indicates the most recent revision.
