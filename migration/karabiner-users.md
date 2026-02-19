---
layout: default
title: Switching from Karabiner-Elements
description: A practical guide for Karabiner-Elements users migrating to KeyPath
---

<div class="migration-hero">
  <h1>From Karabiner.<br>To KeyPath.</h1>
  <p class="migration-hero-subtitle">Keep what you love about keyboard customization. Gain a modern engine built for tap-hold.</p>
</div>

If you're using [Karabiner-Elements](https://karabiner-elements.pqrs.org/) and curious about KeyPath, this page maps the concepts you know to how KeyPath works — and helps you decide if switching makes sense.

---

## Why consider switching?

Karabiner-Elements is an excellent tool that pioneered keyboard remapping on macOS. KeyPath builds on that foundation with a different engine ([Kanata](https://github.com/jtroo/kanata)) that offers specific advantages:

| | Karabiner-Elements | KeyPath |
|---|---|---|
| **Config format** | JSON (verbose, complex) | Kanata S-expressions (concise) |
| **Tap-hold** | `to_if_alone` + timeout | 4 tap-hold variants, per-key tuning |
| **Home row mods** | Complex JSON rules needed | Built-in with split-hand detection |
| **Per-finger timing** | Global timeout only | Individual finger sensitivity |
| **Layers** | Separate rule sets | First-class `deflayer` with layer-switch |
| **App-specific** | Per-app rules via JSON | Automatic layer switching via TCP |
| **Configuration** | JSON editing or Karabiner UI | Visual UI + direct config editing |
| **Engine** | Custom C++ event tap | Kanata (Rust, purpose-built for tap-hold) |

**Karabiner's strengths** that KeyPath doesn't replicate:
- Massive [community rule library](https://ke-complex-modifications.pqrs.org/) with importable JSON rules
- Longer track record (10+ years, widely trusted)
- Simpler mental model for basic remaps

---

## Concept mapping

Here's how Karabiner concepts translate to KeyPath/Kanata:

### Simple remaps

<div style="display: grid; grid-template-columns: 1fr 1fr; gap: 1rem;">
<div markdown="1">

**Karabiner JSON:**
```json
{
  "type": "basic",
  "from": { "key_code": "caps_lock" },
  "to": [{ "key_code": "escape" }]
}
```

</div>
<div markdown="1">

**KeyPath/Kanata:**
```lisp
(defsrc caps)
(deflayer base esc)
```

</div>
</div>

### Tap-hold (dual-role keys)

<div style="display: grid; grid-template-columns: 1fr 1fr; gap: 1rem;">
<div markdown="1">

**Karabiner JSON:**
```json
{
  "type": "basic",
  "from": { "key_code": "caps_lock" },
  "to": [{ "key_code": "left_control" }],
  "to_if_alone": [{ "key_code": "escape" }],
  "parameters": {
    "basic.to_if_alone_timeout_milliseconds": 200
  }
}
```

</div>
<div markdown="1">

**KeyPath/Kanata:**
```lisp
(defalias
  caps (tap-hold 200 200 esc lctl)
)
(defsrc caps)
(deflayer base @caps)
```

</div>
</div>

Kanata's version is more concise and offers [4 tap-hold variants]({{ '/guides/tap-hold' | relative_url }}) with different activation strategies:
- `tap-hold` — pure timeout
- `tap-hold-press` — activates hold on other key press
- `tap-hold-release` — permissive hold, quick tap
- `tap-hold-release-keys` — specific keys trigger early activation

Read the [Tap-Hold guide]({{ '/guides/tap-hold' | relative_url }}) for details on each variant.

### Layers

<div style="display: grid; grid-template-columns: 1fr 1fr; gap: 1rem;">
<div markdown="1">

**Karabiner:** Uses `set_variable` and conditions to simulate layers across multiple rule sets.

</div>
<div markdown="1">

**KeyPath/Kanata:** Layers are a first-class concept:
```lisp
(deflayer base
  @nav  a  s  d  f
)
(deflayer nav
  _     ←  ↓  ↑  →
)
```

</div>
</div>

### Complex modifications

Karabiner's [Complex Modifications](https://ke-complex-modifications.pqrs.org/) are powerful JSON rules. In KeyPath, equivalent functionality uses Kanata's `defalias`, `multi`, `switch`, and `defseq`:

```lisp
;; Hyper key (equivalent to Karabiner complex modification)
(defalias
  hyp (tap-hold 200 200 esc (multi lctl lalt lmet lsft))
)

;; Leader key sequence
(defseq
  open-safari (spc s s)
  open-terminal (spc s t)
)
```

### App-specific rules

<div style="display: grid; grid-template-columns: 1fr 1fr; gap: 1rem;">
<div markdown="1">

**Karabiner:** Per-app conditions in JSON:
```json
"conditions": [{
  "type": "frontmost_application_if",
  "bundle_identifiers": ["^com\\.apple\\.Safari$"]
}]
```

</div>
<div markdown="1">

**KeyPath:** Automatic layer switching. Add an app in the App-Specific Rules tab, configure mappings, and KeyPath switches layers via TCP when you switch apps. See the [Window Management guide]({{ '/guides/window-management' | relative_url }}).

</div>
</div>

---

## What you'll gain

- **Better tap-hold** — Kanata was purpose-built for tap-hold behaviors. Four variants with per-key timing give you control Karabiner can't match. See [Home Row Mods]({{ '/guides/home-row-mods' | relative_url }}).
- **Split-hand detection** — Cross-hand keypresses activate modifiers, same-hand keypresses produce letters. This eliminates most home row mod misfires. Achievable in Karabiner but requires complex JSON.
- **Readable config** — Compare 3 lines of Kanata to 20 lines of Karabiner JSON for the same remap.
- **App launching** — Built-in [Action URI system]({{ '/guides/action-uri' | relative_url }}) for launching apps, opening URLs, and tiling windows from your keyboard.
- **Visual configuration** — KeyPath's SwiftUI interface lets you configure without editing JSON or config files.

## What you'll lose (temporarily)

- **Community rule library** — Karabiner's [importable modifications](https://ke-complex-modifications.pqrs.org/) have no KeyPath equivalent yet. You'll need to recreate rules manually.
- **Some edge-case rules** — Karabiner's JSON is extremely flexible. Some exotic conditions (mouse button combinations, device-specific vendor IDs with complex conditions) may require creative workarounds in Kanata.
- **Track record** — Karabiner has been trusted for 10+ years. KeyPath is newer. Both are open source, so you can verify the code yourself.

---

## Can I run both?

**Not simultaneously.** Both tools intercept keyboard events at the system level, and running two event interceptors causes conflicts (dropped keys, double-presses, system instability). You should fully disable or uninstall Karabiner before using KeyPath.

KeyPath's installer wizard will detect running Karabiner processes and warn you if there's a conflict.

**Note:** KeyPath uses the same [Karabiner VirtualHIDDevice driver](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice) for its virtual keyboard. If you already have Karabiner installed, this driver is already present and approved.

---

## Migration steps

### 1. Document your current setup

Before uninstalling Karabiner, export or screenshot your rules:

```bash
# Your Karabiner config is at:
cat ~/.config/karabiner/karabiner.json

# Or copy it somewhere safe:
cp ~/.config/karabiner/karabiner.json ~/Desktop/karabiner-backup.json
```

### 2. Install KeyPath

Follow the [Installation guide]({{ '/getting-started/installation' | relative_url }}). KeyPath's wizard handles permissions and driver setup.

### 3. Quit Karabiner

Quit Karabiner-Elements from its menu bar icon, or:

```bash
# Quit Karabiner
osascript -e 'quit app "Karabiner-Elements"'

# Optionally stop the daemon
launchctl bootout system/org.pqrs.karabiner.karabiner_grabber 2>/dev/null
```

### 4. Recreate your rules

Start with the basics — remaps you use most — and build up:

1. **Caps Lock remap** — Enable the pre-built rule in KeyPath
2. **Home row mods** — Enable the pre-built rule (much easier than the Karabiner JSON version)
3. **Custom rules** — Recreate your most-used modifications one at a time

See [Your First Mapping]({{ '/getting-started/first-mapping' | relative_url }}) for a walkthrough.

### 5. Fine-tune

KeyPath's per-finger timing and split-hand detection may mean you need less tweaking than your Karabiner setup required. Start with defaults and adjust from there.

---

## Common Karabiner rules → KeyPath equivalents

| Karabiner Rule | KeyPath Equivalent |
|---|---|
| Caps Lock → Escape | Pre-built "Caps Lock Remap" rule |
| Caps Lock → Escape/Control | Pre-built rule with tap-hold |
| Caps Lock → Hyper | Pre-built "Caps Lock Remap" → Hyper mode |
| Home row mods | Pre-built "Home Row Mods" rule |
| Vi-style arrows (HJKL) | Custom rule or [Vim Navigation]({{ '/guides/use-cases#vim-navigation-everywhere' | relative_url }}) |
| App-specific shortcuts | App-Specific Rules tab |
| Launch apps from keyboard | [Action URI system]({{ '/guides/action-uri' | relative_url }}) |
| Window snapping | [Window Management]({{ '/guides/window-management' | relative_url }}) |

---

## Karabiner feature parity

Not every Karabiner feature has a direct KeyPath equivalent yet. Here's the current state:

| Karabiner Feature | KeyPath Status | Notes |
|---|---|---|
| Simple remaps | **Full support** | `defsrc` / `deflayer` |
| Tap-hold / `to_if_alone` | **Full support** | 4 variants, more control than Karabiner |
| Layers | **Full support** | First-class `deflayer` with `layer-switch` / `layer-toggle` |
| App-specific rules | **Full support** | Automatic layer switching via TCP |
| Simultaneous key combos | **Full support** | Kanata `chord` action |
| Mouse button remapping | **Partial** | Kanata supports mouse keys, but Karabiner's mouse button conditions are more flexible |
| Device-specific rules | **Full support** | Kanata's `device-if` in `defcfg` |
| Complex variable conditions | **Partial** | Kanata's `switch` action covers most cases, but some multi-variable conditions need restructuring |
| Profile switching | **Not yet** | Karabiner lets you switch between profiles; KeyPath uses a single config with layers |
| Community rule import | **Not yet** | No equivalent to Karabiner's [Complex Modifications library](https://ke-complex-modifications.pqrs.org/) |
| Pointing device rules | **Limited** | Kanata has mouse key support but not Karabiner's full pointing device condition system |

### Config converter (future)

We're exploring a tool that would let you paste your Karabiner JSON and see the equivalent Kanata config — making migration near-instant for common patterns. If this would be useful to you, let us know in [GitHub Discussions](https://github.com/malpern/KeyPath/discussions) so we can prioritize it.

---

## Further reading

- **[Keyboard Concepts]({{ '/guides/concepts' | relative_url }})** — If you want a refresher on the fundamentals
- **[Home Row Mods]({{ '/guides/home-row-mods' | relative_url }})** — KeyPath's biggest advantage over Karabiner
- **[Tap-Hold & Tap-Dance]({{ '/guides/tap-hold' | relative_url }})** — All four tap-hold variants explained
- **[What You Can Build]({{ '/guides/use-cases' | relative_url }})** — Concrete examples of KeyPath setups
- **[Action URIs]({{ '/guides/action-uri' | relative_url }})** — Launch apps, URLs, and window actions
- **[Privacy & Permissions]({{ '/guides/privacy' | relative_url }})** — How KeyPath's permission model compares
- **[Karabiner-Elements](https://karabiner-elements.pqrs.org/)** — Karabiner's official site ↗
- **[Complex Modifications](https://ke-complex-modifications.pqrs.org/)** — Karabiner's community rule library ↗
- **[Back to Docs]({{ '/docs' | relative_url }})**
