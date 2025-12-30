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

No. KeyPath works completely offline. The only optional feature that requires internet is AI-powered config generation, which requires an `ANTHROPIC_API_KEY` environment variable.

### Is KeyPath free?

Yes, KeyPath is open source and free to use under the MIT License.

### How is KeyPath different from Karabiner-Elements?

KeyPath uses Kanata as its remapping engine, which offers more flexibility and power than Karabiner-Elements. KeyPath provides a native macOS interface for Kanata, handling all the system integration complexity that makes Kanata difficult to use directly.

## Installation & Setup

### Why does KeyPath need a privileged helper?

The privileged helper is used to install and manage LaunchDaemon services and system binaries without requiring repeated password prompts. This ensures KeyPath can reliably manage system-level services.

### Where is the kanata binary installed?

KeyPath installs the kanata binary to `/Library/KeyPath/bin/kanata` for stable TCC (Transparency, Consent, and Control) permissions. This system location ensures consistent permission behavior.

### How do I build KeyPath from source?

Run `./build.sh` — it builds, signs, notarizes, deploys to `~/Applications`, and restarts the app. For local iteration without notarization, use `SKIP_NOTARIZE=1 ./build.sh`.

### Can I use KeyPath alongside Karabiner-Elements?

No. KeyPath and Karabiner-Elements both use the Karabiner VirtualHID driver, which can only be used by one application at a time. KeyPath's setup wizard will detect and help resolve conflicts.

## Configuration

### Where are my configurations stored?

User configurations are stored at `~/.config/keypath/keypath.kbd`. KeyPath also generates `keypath-apps.kbd` in the same directory for app-specific rules.

### Can I edit the config file directly?

Yes! KeyPath preserves your custom configuration. If you edit `keypath.kbd` directly, KeyPath will hot-reload the changes via TCP. Just make sure to keep the `(include keypath-apps.kbd)` line at the top.

### Why doesn't KeyPath show my custom rules in the UI?

KeyPath doesn't parse Kanata config files to populate the UI. The UI only shows rules created through KeyPath's interface. Your BYOC (Bring Your Own Config) rules work perfectly, but they're invisible to the UI. This is by design to avoid maintaining a shadow parser.

### Can I migrate from Karabiner-Elements?

KeyPath doesn't directly import Karabiner-Elements configurations, but you can manually convert your rules. See the [Migration Guide](/migration/kanata-users) for details on bringing your own Kanata config.

## Permissions

### Why does KeyPath need Input Monitoring permission?

Input Monitoring allows KeyPath to detect key presses. This is required for keyboard remapping to work.

### Why does KeyPath need Accessibility permission?

Accessibility permission allows KeyPath to send remapped key events to applications. This is required for the remapped keys to actually work.

### Can I grant permissions manually?

Yes. Go to System Settings → Privacy & Security → Input Monitoring (or Accessibility) and enable KeyPath manually. Then restart the app.

## Troubleshooting

### Keys aren't remapping. What should I do?

1. Check the status indicator in KeyPath — look for green checkmarks
2. Verify permissions are granted in System Settings
3. Click "Fix Issues" in KeyPath for automated fixes
4. Check logs: `tail -f /var/log/com.keypath.kanata.stdout.log`

### The setup wizard won't complete

1. Check for conflicting processes (Karabiner, other Kanata instances)
2. Use the "Fix Issues" button in the wizard
3. Check logs for specific error messages
4. Restart the app and try again

### KeyPath crashes or becomes unresponsive

Press **Ctrl + Space + Esc** simultaneously to immediately disable all remappings. This is KeyPath's emergency stop feature.

### How do I view logs?

KeyPath logs are written to `/var/log/com.keypath.kanata.stdout.log`. View them with:

```bash
tail -f /var/log/com.keypath.kanata.stdout.log
```

## Advanced

### How does KeyPath communicate with Kanata?

KeyPath uses TCP (default port 37001) to communicate with Kanata. This enables hot-reload, config validation, and overlay UI features.

### Can I use a custom TCP port?

Yes, but you'll need to update both your Kanata config (`defcfg`) and KeyPath's service configuration to match.

### Does KeyPath support multiple keyboards?

Yes, KeyPath supports multiple keyboards. Device filtering in your Kanata config works as expected.

### Can I use KeyPath with a custom Kanata binary?

KeyPath manages its own Kanata binary installation. Using a custom binary may cause permission and service management issues.

## Development

### How do I contribute?

See the [Contributing Guide]({{ site.github_url }}/blob/main/CONTRIBUTING.md) for details. KeyPath welcomes contributions!

### Where can I report bugs?

Report bugs on [GitHub Issues]({{ site.github_url }}/issues).

### How do I run tests?

```bash
swift test
```

For tests requiring sudo (privileged operations):

```bash
KEYPATH_USE_SUDO=1 swift test
```

## Still Have Questions?

- [GitHub Discussions]({{ site.github_url }}/discussions)
- [GitHub Issues]({{ site.github_url }}/issues)
- [Debugging Guide](/guides/debugging)
