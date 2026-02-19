---
layout: default
title: Activity Insights
description: Optional plugin that tracks your keyboard usage patterns — installed separately, on your terms
---

# Activity Insights

Activity Insights is an **optional plugin** for KeyPath that tracks keyboard usage patterns, shortcut frequency, and app switching habits. It is not part of KeyPath itself — it's a separate plugin bundle you choose to install.

---

## Why a separate plugin?

KeyPath is a keyboard remapper. It intercepts every keystroke you type, transforms it according to your rules, and sends it to your apps. That's a lot of trust. We didn't want to add analytics on top of that and ask you to just trust us further.

So we made a decision: **KeyPath itself contains zero tracking code.** No analytics. No usage metrics. No data collection of any kind. The core app remaps your keys and nothing else.

If you *want* to understand your keyboard habits — which shortcuts you actually use, how often you switch apps, whether your custom layers are paying off — that's where Activity Insights comes in. It's a plugin you install deliberately, and the act of installing it is the act of consenting to local data collection. No hidden checkboxes. No "opt out" buried in settings. You either have the plugin or you don't.

```
  Without plugin:                With plugin installed:

  ┌──────────────┐              ┌──────────────┐
  │  KeyPath     │              │  KeyPath     │
  │              │              │              │
  │  Remaps keys │              │  Remaps keys │
  │  Zero data   │              │       │      │
  │  collection  │              │       ↓      │
  │              │              │  ┌─────────┐ │
  └──────────────┘              │  │Insights │ │
                                │  │ plugin  │ │
                                │  │         │ │
                                │  │ Local   │ │
                                │  │ storage │ │
                                │  └─────────┘ │
                                └──────────────┘
```

---

## What it tracks

When the plugin is installed and enabled, Activity Insights records:

- **App switches** — which apps you switch between and how often
- **App launches** — when applications are opened
- **KeyPath action events** — when your custom `keypath://` action URIs fire (layer switches, app launchers, window management, etc.)

### What it does NOT track

- **Individual keystrokes** — Insights does not record what you type. It only sees action URI events that fire from your rules.
- **Passwords or text input** — No keystroke logging of any kind.
- **Screen content** — No screenshots or window content.
- **Network data** — Nothing is ever sent anywhere. All data stays on your Mac.

---

## How data is stored

All activity data is stored locally in encrypted files:

| What | Where |
|---|---|
| Encrypted logs | `~/Library/Application Support/KeyPath/ActivityLog/*.enc` |
| Encryption key | macOS Keychain (device-bound, never exported) |

- **AES-256-GCM encryption** — Events are encrypted before writing to disk
- **Keychain-bound key** — The encryption key is stored in your macOS Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, meaning it can't be extracted or transferred to another Mac
- **Monthly file rotation** — Logs are split into monthly files for manageable storage
- **JSON Lines format** — Each event is a single JSON line (inside the encrypted envelope), making the format simple and inspectable if you decrypt it yourself

---

## What you can learn

Activity Insights generates reports showing:

- **Top apps** — Which apps you use most, ranked by switches
- **Top shortcuts** — Which keyboard shortcuts and action URIs you trigger most often
- **KeyPath actions** — How often your custom rules fire, helping you understand which remappings you actually use
- **Daily / Weekly / Monthly** breakdowns — See patterns over time

This helps you answer questions like:
- "Am I actually using those home row mods I set up?"
- "Which apps would benefit most from a dedicated KeyPath layer?"
- "How often do I trigger my window management shortcuts?"

---

## Installing the plugin

Activity Insights is available directly from KeyPath's Settings:

1. Open **KeyPath Settings** (Cmd+,)
2. Go to the **Experimental** tab
3. Find the **Activity Insights** card under "Optional Add-On"
4. Click **Download & Install**

The plugin downloads (~2 MB), installs to `~/Library/Application Support/KeyPath/Plugins/`, and activates immediately — no restart needed.

You can also install it manually by placing `Insights.bundle` in `~/Library/Application Support/KeyPath/Plugins/`.

---

## Enabling and disabling

After installing the plugin, you'll see its settings panel in Settings > Experimental:

- **Enable** — Shows a consent dialog explaining what will be tracked. You must acknowledge that data is stored locally and encrypted before logging starts.
- **Disable** — Stops recording immediately. Existing data is preserved.
- **View Report** — Opens a report window showing your usage patterns.
- **Reset Data** — Permanently deletes all recorded activity data.

---

## Removing the plugin

To completely remove Activity Insights:

1. Open **KeyPath Settings** > **Experimental**
2. Click **Remove Plugin** at the bottom of the Insights card
3. Confirm the removal

This deletes the plugin bundle from disk. Your logged data files are preserved in case you reinstall later — use **Reset Data** before removing if you want to delete everything.

After removal, the Insights settings card disappears and the "Optional Add-On" discovery card returns. KeyPath is back to zero tracking code.

---

## Privacy summary

| Question | Answer |
|---|---|
| Does installing the plugin send data anywhere? | No. Everything stays on your Mac. |
| Can I see what's being collected? | Yes. View Report shows all recorded data. |
| Can I delete my data? | Yes. Reset Data permanently deletes everything. |
| Can I remove the plugin entirely? | Yes. Remove Plugin deletes the bundle from disk. |
| Does KeyPath track anything without the plugin? | No. Zero data collection in the base app. |
| Is the data encrypted? | Yes. AES-256-GCM with a device-bound Keychain key. |
| Could a backup tool capture my activity data? | The encrypted files are on disk, so Time Machine would back them up. But without the Keychain key (device-bound), the data is unreadable on any other machine. |

For KeyPath's full privacy practices, see [Privacy & Permissions]({{ '/guides/privacy' | relative_url }}).

---

## Technical details

Activity Insights uses KeyPath's plugin architecture:

- **Plugin bundle:** `Insights.bundle` loaded at runtime via `NSPrincipalClass`
- **Protocol:** Conforms to `KeyPathPlugin` from the shared `KeyPathPluginKit` dynamic library
- **Action forwarding:** KeyPath's `ActionDispatcher` broadcasts all `keypath://` URI events to loaded plugins
- **No static linking:** The plugin is not compiled into KeyPath. Removing the `.bundle` file removes all Insights code from the running app.

Source code: [`Sources/KeyPathInsights/`]({{ site.github_url }}/tree/master/Sources/KeyPathInsights)

---

- **[Privacy & Permissions]({{ '/guides/privacy' | relative_url }})** — Full privacy practices for KeyPath
- **[FAQ]({{ '/faq' | relative_url }})** — More questions about KeyPath and Insights
- **[Back to Docs]({{ '/docs' | relative_url }})**
