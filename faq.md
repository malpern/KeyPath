---
layout: default
title: FAQ
description: Common questions about KeyPath
permalink: /faq/
---

# FAQ

## What is KeyPath?

KeyPath is a macOS app for keyboard remapping. It guides you through permissions, runs the background service reliably, and gives you a fast way to diagnose problems.

## Do I need to know Kanata?

No. You can use KeyPath without touching a config file.

If you already use Kanata, KeyPath can also run your existing `.kbd` config. Start here: **[KeyPath for Kanata users]({{ '/kanata' | relative_url }})**.

## Why does KeyPath ask for permissions?

macOS requires permissions for apps that listen to and remap keyboard input.

- **Input Monitoring**: required for remapping
- **Accessibility**: required for some automation features (like window management)

## Where is the config file?

KeyPath’s default config location is:

`~/.config/keypath/keypath.kbd`

## I installed it, but nothing is remapping. What should I do?

Run the setup wizard again and use the **Fix** button. It checks:

- Permissions
- Conflicts (other remappers)
- Service health / restarts

## How do I migrate from Kanata?

Use the short migration guide:

- **[Migrating from Kanata]({{ '/migration/kanata-users' | relative_url }})**

## How do I report a bug?

Open an issue on GitHub:

- [GitHub Issues]({{ site.github_url }}/issues)
