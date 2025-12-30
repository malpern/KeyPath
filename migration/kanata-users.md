---
layout: default
title: Migrating from Kanata
description: Bring your existing Kanata configuration to KeyPath
permalink: /migration/kanata-users/
---

# Migrating from Kanata to KeyPath

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

## What to expect

- **Your config stays yours**: KeyPath runs it; it doesn’t parse/import it into a UI.
- **KeyPath generates one helper file**: `keypath-apps.kbd` (don’t edit it).
- **If things break**: open the wizard and hit “Fix”.

## Gotchas (quick)

- Keep `(include keypath-apps.kbd)` first.
- If you use a custom TCP port, make sure it matches KeyPath’s service settings.

## Need help?

- [Open an issue]({{ site.github_url }}/issues)
- [FAQ]({{ '/faq' | relative_url }})
