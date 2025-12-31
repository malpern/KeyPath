---
layout: default
title: FAQ
description: Frequently asked questions about KeyPath
---

# Frequently Asked Questions

## General

### What macOS version is required?

macOS 15.0 (Sequoia) or later. KeyPath works on both Apple Silicon and Intel Macs.

### Do I need an internet connection?

No. KeyPath works completely offline. The only exception is the optional AI config generation feature, which requires an `ANTHROPIC_API_KEY` environment variable if you want to use it.

### Is KeyPath free and open source?

Yes! KeyPath is open source under the MIT License. You can view the source code, contribute, and use it freely.

## Installation & Setup

### Why does KeyPath need a privileged helper?

The privileged helper is used to install and manage LaunchDaemon services and system binaries without requiring repeated password prompts. This ensures KeyPath can reliably manage system-level components.

### Where is the Kanata binary installed?

KeyPath installs Kanata to `/Library/KeyPath/bin/kanata` for stable TCC (Transparency, Consent, and Control) permissions. This system location ensures consistent permission handling.

### Can I use my own Kanata binary?

Yes! If you have Kanata installed via Homebrew or another method, KeyPath can use it. However, the bundled Developer ID signed binary is recommended for best compatibility and security.

## Usage

### Why doesn't the GUI create CGEvent taps directly?

The LaunchDaemon (root process) owns the event taps to avoid conflicts and prevent lockups. This architecture ensures reliable operation even if the GUI crashes.

### How do I uninstall KeyPath?

1. Open KeyPath
2. Choose **File → Uninstall KeyPath…**
3. Confirm the admin prompt

This removes all components including services, binaries, and configuration files.

### Can I edit the config file directly?

Yes! KeyPath preserves your custom configuration. If you edit `~/.config/keypath/keypath.kbd` directly, KeyPath will detect changes and hot-reload them via TCP.

**Note:** Sections marked with `;; === KEYPATH MANAGED ===` may be overwritten when you save from the UI. Your custom sections are always preserved.

## Configuration

### How do I migrate from standalone Kanata?

See the [Migration Guide](/migration/kanata-users) for complete instructions. The quick path:

1. Copy your config to `~/.config/keypath/keypath.kbd`
2. Add `(include keypath-apps.kbd)` at the top
3. Run KeyPath's setup wizard

### Can I use symlinks for my config?

Yes, but with caution. KeyPath generates `keypath-apps.kbd` in `~/.config/keypath/`. If your symlink points elsewhere, the include may fail. It's safer to copy your config or use KeyPath's migration wizard.

### What TCP port does KeyPath use?

Default port is `37001`. You can configure a custom port in your `defcfg`:

```lisp
(defcfg
  tcp-server-port 37001
)
```

## Troubleshooting

### Keys aren't remapping

1. **Check status indicator** - Look for green checkmarks in the app
2. **Verify permissions** - Ensure Input Monitoring and Accessibility are granted
3. **Use Fix Issues** - Click "Fix Issues" button in the app
4. **Check logs** - `tail -f /var/log/com.keypath.kanata.stdout.log`

### Setup wizard won't complete

1. Check for conflicting processes (Karabiner, other Kanata instances)
2. Verify permissions are granted in System Settings
3. Check logs for specific error messages
4. Try restarting the app and running the wizard again

### Service keeps crashing

1. Check logs: `tail -f /var/log/com.keypath.kanata.stdout.log`
2. Verify config syntax is valid
3. Use the "Fix Issues" button in the wizard
4. Check for conflicts with other remappers

### Emergency stop

If your keyboard becomes unresponsive, press **Ctrl + Space + Esc** simultaneously. This immediately disables all remappings and restores normal keyboard functionality.

## Development

### How do I build KeyPath from source?

```bash
git clone {{ site.github_url }}.git
cd KeyPath
./build.sh
```

The build script builds, signs, notarizes, deploys to `~/Applications`, and restarts the app.

**For local iteration:** `SKIP_NOTARIZE=1 ./build.sh`

### How do I run tests?

```bash
swift test
```

For tests requiring sudo: `KEYPATH_USE_SUDO=1 swift test`

### How do I contribute?

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests and ensure code quality
5. Submit a pull request

See [CONTRIBUTING.md]({{ site.github_url }}/blob/main/CONTRIBUTING.md) for detailed guidelines.

## Architecture

### Why doesn't KeyPath parse config files?

KeyPath follows [ADR-023](/adr/adr-023-no-config-parsing): Kanata is the source of truth. Parsing would create a shadow implementation that can drift. Instead, KeyPath uses TCP and the simulator to understand config state.

### How does the two-file model work?

KeyPath uses `keypath.kbd` (user-owned) and `keypath-apps.kbd` (KeyPath-generated). Your config includes the generated file to access app-specific virtual keys. See [ADR-027](/adr/adr-027-app-specific-keymaps) for details.

### What is the InstallerEngine?

The `InstallerEngine` is a unified façade for all install/repair/uninstall operations. It's the single entry point for system modifications. See [ADR-015](/adr/adr-015-installer-engine) for details.

## AI Config Generation

### Do I need an API key to use KeyPath?

No! KeyPath works without an API key for simple single-key remaps. AI is only needed for complex mappings like sequences, chords, and macros.

### How much does AI generation cost?

Each complex mapping costs approximately $0.01-0.03. Simple mappings are always free (no API call). These are estimates—check your [Anthropic dashboard](https://console.anthropic.com/) for exact charges.

### Is my API key secure?

Yes. Your API key is stored securely in the macOS Keychain using `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. It's never sent anywhere except to Anthropic's API.

### Can I track my AI usage?

Yes! Go to Settings → General → AI Config Generation → "View Usage History" to see estimated costs and token usage.

### What if I don't have an API key?

KeyPath will:
- ✅ Work for simple single-key remaps
- ⚠️ Use basic generation for complex mappings (may not work for all cases)
- ❌ Not be able to generate advanced sequences, chords, or macros

### How do I get an API key?

1. Go to [console.anthropic.com/settings/keys](https://console.anthropic.com/settings/keys)
2. Create an account if needed
3. Generate a new API key (starts with `sk-ant-`)
4. Add it in Settings → General → AI Config Generation

For full details, see the [AI Config Generation guide](/guides/ai-config-generation).

## Security & Privacy

### Does KeyPath collect data?

No. KeyPath works completely offline and collects no telemetry or user data. The only external communication is with Anthropic's API (if you've enabled AI config generation).

### What permissions does KeyPath need?

- **Input Monitoring** - To detect key presses
- **Accessibility** - To send remapped keys

These are standard permissions required for keyboard remapping on macOS.

### Is KeyPath notarized?

Yes. Official releases are notarized by Apple, ensuring they work with macOS security features.

## Still Have Questions?

- [GitHub Issues]({{ site.github_url }}/issues) - Report bugs or ask questions
- [Discussions]({{ site.github_url }}/discussions) - Community discussions
- [Debugging Guide](/guides/debugging) - Advanced troubleshooting
