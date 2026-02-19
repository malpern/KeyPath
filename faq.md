---
layout: default
title: FAQ
description: Frequently asked questions about KeyPath
---

# Frequently Asked Questions

## General

### What macOS version is required?

macOS 15.0 (Sequoia) or later. Currently **Apple Silicon only** (Intel support coming soon).

### Do I need an internet connection?

No. KeyPath works completely offline. The only network request is an optional update check (via [Sparkle](https://sparkle-project.org/)), which you can disable in Settings.

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

**KeyPath detects your existing config automatically.** On first launch, it checks:
- Running Kanata process (gets config path from args)
- Common locations (`~/.config/kanata/`, home directory)

When found, click "Use This Config" and you're done. KeyPath symlinks to your original file and adds the include line it needs. Your config stays where it is.

See the [Kanata Migration Guide]({{ '/migration/kanata-users' | relative_url }}) for details. Switching from Karabiner-Elements? See the [Karabiner Migration Guide]({{ '/migration/karabiner-users' | relative_url }}).

### Can I keep my config in its original location?

Yes — that's the default. KeyPath creates a symlink to your original file rather than copying it. Edit your config wherever you like; KeyPath hot-reloads changes automatically.

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

KeyPath follows [ADR-023]({{ site.github_url }}/blob/main/docs/adr/adr-023-no-config-parsing.md): Kanata is the source of truth. Parsing would create a shadow implementation that can drift. Instead, KeyPath uses TCP and the simulator to understand config state.

### How does the two-file model work?

KeyPath uses `keypath.kbd` (user-owned) and `keypath-apps.kbd` (KeyPath-generated). Your config includes the generated file to access app-specific virtual keys. See [ADR-027]({{ site.github_url }}/blob/main/docs/adr/adr-027-app-specific-keymaps.md) for details.

### What is the InstallerEngine?

The `InstallerEngine` is a unified façade for all install/repair/uninstall operations. It's the single entry point for system modifications. See [ADR-015]({{ site.github_url }}/blob/main/docs/adr/adr-015-installer-engine.md) for details.

## Security & Privacy

### Does KeyPath collect data?

No. KeyPath itself contains zero tracking code — no analytics, no telemetry, no usage metrics. The only network request is an optional update check, which you can disable. Usage analytics are available as a [separate plugin]({{ '/guides/activity-insights' | relative_url }}) that you install explicitly; if you don't install it, the code isn't there.

### What permissions does KeyPath need?

- **Input Monitoring** - To detect key presses
- **Accessibility** - To send remapped keys

These are standard permissions required for keyboard remapping on macOS.

### Why does KeyPath optionally request Full Disk Access?

Full Disk Access is **optional** and only needed if you want KeyPath to verify Kanata's permissions. Without it, KeyPath can still function normally, but it won't be able to check whether Kanata has been granted Input Monitoring and Accessibility permissions.

KeyPath uses Full Disk Access to read the system TCC (Transparency, Consent, and Control) database, which stores permission grants. This read-only operation allows KeyPath to:

- Verify Kanata's permissions before starting the service
- Show accurate permission status in the UI
- Guide you through permissions sequentially (rather than triggering multiple dialogs at once)

**KeyPath works without Full Disk Access**—you can grant permissions directly to Kanata in System Settings, and KeyPath will function normally. Full Disk Access is purely a convenience feature for better permission verification and UX.

### Is KeyPath notarized?

Yes. Official releases are notarized by Apple, ensuring they work with macOS security features.

## Activity Insights Plugin

### What is Activity Insights?

[Activity Insights]({{ '/guides/activity-insights' | relative_url }}) is an optional plugin for KeyPath that tracks keyboard usage patterns — which shortcuts you use, how often you switch apps, and which action URIs fire. It's not compiled into KeyPath. You install it separately from Settings > Experimental, and the install act is the consent act. All data is encrypted and stored locally on your Mac.

### Do I need the Activity Insights plugin?

No. KeyPath works fully on its own with zero data collection. The Insights plugin is for people who want to understand their keyboard habits — like discovering which shortcuts they actually use or which apps would benefit from a dedicated layer.

### How do I install or remove it?

Install from **Settings > Experimental > Activity Insights > Download & Install**. Remove from the same panel by clicking **Remove Plugin**. No restart needed either way. See the [Activity Insights]({{ '/guides/activity-insights' | relative_url }}) page for details.

### Does the plugin send data anywhere?

No. All data stays on your Mac in AES-256-GCM encrypted files. The encryption key is bound to your device via the macOS Keychain. Nothing is ever transmitted.

## Still Have Questions?

- **[GitHub Issues]({{ site.github_url }}/issues)** — Report bugs or ask questions
- **[Discussions]({{ site.github_url }}/discussions)** — Community discussions
- **[Debugging Guide]({{ '/guides/debugging' | relative_url }})** — Advanced troubleshooting
- **[Privacy & Permissions]({{ '/guides/privacy' | relative_url }})** — What KeyPath accesses and why
- **[Activity Insights]({{ '/guides/activity-insights' | relative_url }})** — Optional usage analytics plugin
- **[Keyboard Concepts]({{ '/guides/concepts' | relative_url }})** — Layers, tap-hold, modifiers explained
- **[Home Row Mods]({{ '/guides/home-row-mods' | relative_url }})** — The most popular advanced technique
- **[Tap-Hold & Tap-Dance]({{ '/guides/tap-hold' | relative_url }})** — All tap-hold options explained
- **[Your First Mapping]({{ '/getting-started/first-mapping' | relative_url }})** — Step-by-step getting started
- **[Kanata documentation](https://github.com/jtroo/kanata/blob/main/docs/config.adoc)** — Full Kanata config reference ↗
- **[Back to Docs]({{ '/docs' | relative_url }})**
