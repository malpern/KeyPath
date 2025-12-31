---
layout: default
title: Tips for existing Kanata users
description: Use your existing Kanata config.kbd in KeyPath
permalink: /migration/kanata-users/
---

# Tips for existing Kanata users
If you’re already using Kanata, you’re the exact audience for KeyPath.

If you want the short pitch first, start here: **[KeyPath for Kanata users]({{ '/kanata' | relative_url }})**.

## The only steps you need

1) Put your config where KeyPath looks:

```bash
mkdir -p ~/.config/keypath
cp ~/.config/kanata/kanata.kbd ~/.config/keypath/keypath.kbd
```

2) Add this at the very top of `~/.config/keypath/keypath.kbd`:

```lisp
(include keypath-apps.kbd)
```

3) Open KeyPath and run the setup wizard (permissions + service install).

## What you get (even with “bring your own config”)

- **macOS setup, handled**: guided Input Monitoring + Accessibility.
- **A reliable background service**: LaunchDaemon install + restart + health checks.
- **Conflict detection + quick fixes**: the wizard can usually repair things in one click.

## What to expect

- **Your config stays yours**: KeyPath runs it; it doesn’t parse/import it into a UI.
- **KeyPath generates one helper file**: `keypath-apps.kbd` (don’t edit it).
- **If things break**: open the wizard and hit “Fix”.

## The two-file model (30 seconds)

KeyPath keeps a clear ownership boundary:

```
~/.config/keypath/
  keypath.kbd       ← yours (keep editing this)
  keypath-apps.kbd  ← generated (KeyPath rewrites this)
```

The only thing you must do is keep this first line at the top of `keypath.kbd`:

```lisp
(include keypath-apps.kbd)
```

## Gotchas (quick)

- Keep `(include keypath-apps.kbd)` first.
- If you use a custom TCP port, make sure it matches KeyPath’s service settings.

## Limitations (quick, honest)

- **No importing into a UI**: KeyPath won’t “read” your `.kbd` and turn it into UI rules.
- **UI/overlay may be incomplete**: some advanced constructs won’t display perfectly.
- **Managed sections can change**: if you use KeyPath’s UI, it may regenerate its own managed blocks (your custom text outside those blocks is preserved).

## Troubleshooting (fast checks)

- **Nothing happens?** Re-run the setup wizard and hit **Fix**.
- **Config won’t load?** Confirm the include line is first and both files are in `~/.config/keypath/`.
- **Using a non-default TCP port?** Make sure KeyPath’s settings and your `defcfg` match.

## Advanced: symlink your config

If you keep configs in dotfiles, symlink works too:

```bash
mkdir -p ~/.config/keypath
ln -s ~/.config/kanata/kanata.kbd ~/.config/keypath/keypath.kbd
```

Just keep `keypath-apps.kbd` in `~/.config/keypath/` so the include resolves.

## Need help?

- [Open an issue]({{ site.github_url }}/issues)
- [FAQ]({{ '/faq' | relative_url }})
