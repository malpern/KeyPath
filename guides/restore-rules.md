---
layout: default
title: "Restore your rules"
description: "Recover an earlier set of KeyPath rules"
theme: parchment
permalink: /guides/restore-rules/
---

# Restore your rules

Open **Settings → Repair/Remove → Configuration Backups**. Choose **Restore** beside the version you want, then confirm. KeyPath saves your current setup before restoring the selected rules and their configuration. Up to five recent backups are kept.

If KeyPath is stopped, the rules are saved and will apply when you start it. If the running keyboard service rejects the restored rules, KeyPath puts the previous version back and reports the failure.

**Open** lets you inspect the saved configuration. Older config-only backups do not include the editor data needed for automatic restoration; their Restore button is disabled.

A backup that cannot be reproduced with your current app-specific rules, keyboard or layout is refused. Your current setup is preserved, and you can open the backup to recover individual rules manually.
