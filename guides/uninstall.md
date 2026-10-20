---
layout: default
title: "Uninstall KeyPath"
description: "Back up your rules and remove KeyPath for a fresh reinstall"
permalink: /guides/uninstall/
---

# Uninstall KeyPath

Open **Settings → Advanced → Uninstall KeyPath…**, then choose **Back Up and Uninstall**.

KeyPath stops remapping and restores keyboard mappings it owns. It saves your rules,
preferences, and app data in a private **KeyPath-Uninstall-Backup-…** folder in
**Downloads**, removes the active settings and caches, moves the app to Trash, and
quits. Keep the backup if you may want your rules later; `README.txt` identifies the
original locations and `preferences.plist` contains your saved preferences.

Reinstalling starts with fresh KeyPath settings. macOS permission grants remain,
so previously approved permission steps may already be complete.

If backup or keyboard cleanup fails, nothing is removed. If a later removal step
fails, the dialog identifies the backup folder and explains the failure.

A configuration folder that is itself a symbolic link is backed up and detached;
its original target is preserved. If a parent folder such as `~/.config` is linked,
uninstall refuses to delete through it. Move KeyPath's settings to a local folder
before retrying.

Dragging the app to Trash in Finder keeps your settings. Use the Settings action
when you want a fresh reinstall.
