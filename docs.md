---
layout: default
title: Documentation
description: Guides and references for KeyPath keyboard remapping on macOS
hide_sidebar: true
content_class: content-full docs-landing
permalink: /docs
theme: parchment
---

<div class="docs-hero">
  <img class="docs-hero-banner" src="{{ '/images/help/header-banner.png' | relative_url }}" alt="">
  <div class="docs-hero-content">
    <h1>KeyPath Documentation</h1>
    <p class="docs-hero-subtitle">Everything you need to master keyboard remapping on your Mac</p>
    <div class="docs-hero-cta">
      <a href="{{ '/guides/concepts/' | relative_url }}" class="docs-cta-primary">New here? Start with Keyboard Concepts</a>
      <a href="{{ '/getting-started/installation/' | relative_url }}" class="docs-cta-secondary">Jump to Installation</a>
    </div>
  </div>
</div>

<div class="docs-grid">

<div class="docs-card">
<h3><a href="{{ '/getting-started/installation/' | relative_url }}">Getting Started</a></h3>
<p>Install KeyPath and get your keyboard remapping in two minutes flat.</p>
<ul class="docs-card-links">
<li><a href="{{ '/getting-started/installation/' | relative_url }}">Setting Up KeyPath</a></li>
<li><a href="{{ '/guides/concepts/' | relative_url }}">Keyboard Concepts</a></li>
<li><a href="{{ '/guides/use-cases/' | relative_url }}">What You Can Build</a></li>
</ul>
</div>

<div class="docs-card docs-card-featured">
<h3><a href="{{ '/guides/concepts/' | relative_url }}">Core Features</a></h3>
<p>The three fundamentals of keyboard remapping — powered by the <a href="https://github.com/jtroo/kanata">Kanata</a> engine. KeyPath provides the visual interface; Kanata provides the power.</p>

<div class="docs-card-spine">
<ul class="docs-card-links">
<li><a href="{{ '/guides/concepts/' | relative_url }}"><strong>Remapping</strong> — Make any key do something else</a></li>
<li><a href="{{ '/guides/tap-hold/' | relative_url }}"><strong>Tap-Hold</strong> — One key, two actions</a></li>
<li><a href="{{ '/guides/concepts/' | relative_url }}"><strong>Layers</strong> — A whole new keyboard at your fingertips</a></li>
</ul>
</div>

<p class="docs-card-secondary-label">Built on the fundamentals:</p>
<ul class="docs-card-links docs-card-links-compact">
<li><a href="{{ '/guides/home-row-mods/' | relative_url }}">Home Row Mods</a></li>
<li><a href="{{ '/guides/chords/' | relative_url }}">Chords</a></li>
<li><a href="{{ '/guides/auto-shift/' | relative_url }}">Auto-Shift</a></li>
<li><a href="{{ '/guides/leader-key/' | relative_url }}">Leader Key</a></li>
<li><a href="{{ '/guides/key-repeat-control/' | relative_url }}">Key Repeat Control</a></li>
</ul>
</div>

<div class="docs-card">
<h3><a href="{{ '/guides/simple-packs/' | relative_url }}">Packs & Layers</a></h3>
<p>Installable feature packs and layer configurations. Browse the catalog, install with one click, customize to fit.</p>
<ul class="docs-card-links">
<li><a href="{{ '/guides/simple-packs/' | relative_url }}">Quick Tweaks</a></li>
<li><a href="{{ '/guides/vim-navigation/' | relative_url }}">Vim Navigation</a></li>
<li><a href="{{ '/guides/numpad-layer/' | relative_url }}">Numpad Layer</a></li>
<li><a href="{{ '/guides/symbol-layer/' | relative_url }}">Symbol Layer</a></li>
<li><a href="{{ '/guides/fun-layer/' | relative_url }}">Function Layer</a></li>
<li><a href="{{ '/guides/quick-launcher/' | relative_url }}">Quick Launcher</a></li>
</ul>
</div>

<div class="docs-card">
<h3><a href="{{ '/guides/siri-and-shortcuts/' | relative_url }}">Automation</a></h3>
<p>Control KeyPath with Siri, automate with Shortcuts, script with Hammerspoon, or use the command line.</p>
<ul class="docs-card-links">
<li><a href="{{ '/guides/siri-and-shortcuts/' | relative_url }}">Siri & Shortcuts</a></li>
<li><a href="{{ '/guides/hammerspoon/' | relative_url }}">Hammerspoon</a></li>
<li><a href="{{ '/guides/cli/' | relative_url }}">Command Line</a></li>
<li><a href="{{ '/guides/action-uri/' | relative_url }}">Launching Apps</a></li>
<li><a href="{{ '/guides/window-management/' | relative_url }}">Window Management</a></li>
</ul>
</div>

<div class="docs-card">
<h3><a href="{{ '/guides/kindavim/' | relative_url }}">App Integrations</a></h3>
<p>KeyPath working alongside other tools — Vim emulation, terminal workflows, and more.</p>
<ul class="docs-card-links">
<li><a href="{{ '/guides/kindavim/' | relative_url }}">KindaVim</a></li>
<li><a href="{{ '/guides/neovim-terminal/' | relative_url }}">Neovim in the Terminal</a></li>
</ul>
</div>

<div class="docs-card">
<h3><a href="{{ '/guides/keyboard-layouts/' | relative_url }}">Keyboard Support</a></h3>
<p>Using a non-standard layout or a custom keyboard? KeyPath adapts.</p>
<ul class="docs-card-links">
<li><a href="{{ '/guides/keyboard-layouts/' | relative_url }}">Works With Your Keyboard</a></li>
<li><a href="{{ '/guides/alternative-layouts/' | relative_url }}">Alternative Layouts</a></li>
</ul>
</div>

<div class="docs-card">
<h3><a href="{{ '/guides/action-uri-reference/' | relative_url }}">Reference</a></h3>
<p>Technical references for scripting, privacy details, and troubleshooting.</p>
<ul class="docs-card-links">
<li><a href="{{ '/guides/action-uri-reference/' | relative_url }}">Action URI Reference</a></li>
<li><a href="{{ '/guides/privacy/' | relative_url }}">Privacy & Permissions</a></li>
</ul>
</div>

<div class="docs-card">
<h3><a href="{{ '/migration/karabiner-users/' | relative_url }}">Switching Tools</a></h3>
<p>Coming from Karabiner-Elements, Kanata, or another remapper? We've got you covered.</p>
<ul class="docs-card-links">
<li><a href="{{ '/migration/karabiner-users/' | relative_url }}">From Karabiner-Elements</a></li>
<li><a href="{{ '/migration/kanata-users/' | relative_url }}">From Kanata</a></li>
</ul>
</div>

</div>

<hr class="docs-divider">

<h2 class="docs-section-heading">Developer Documentation</h2>
<p class="docs-section-subtitle">Contributing to KeyPath or building integrations? These interactive architecture guides cover the internals.</p>

<div class="docs-grid">

<div class="docs-card">
<h3><a href="{{ '/architecture/' | relative_url }}">Architecture Guides</a></h3>
<p>Interactive visual walkthroughs of KeyPath's internal systems, data flows, and design decisions.</p>
<ul class="docs-card-links">
<li><a href="{{ '/architecture/wizard-architecture.html' | relative_url }}">Installation Wizard</a></li>
<li><a href="{{ '/architecture/overlay-architecture.html' | relative_url }}">Live Keyboard Overlay</a></li>
<li><a href="{{ '/architecture/runtime-architecture.html' | relative_url }}">Runtime & Service Lifecycle</a></li>
<li><a href="{{ '/architecture/permissions-architecture.html' | relative_url }}">PermissionOracle</a></li>
<li><a href="{{ '/architecture/rules-architecture.html' | relative_url }}">Rule Collections & Config</a></li>
<li><a href="{{ '/architecture/xpc-architecture.html' | relative_url }}">Privileged Helper & XPC</a></li>
<li><a href="{{ '/architecture/layouts-architecture.html' | relative_url }}">Keyboard Layouts</a></li>
<li><a href="{{ '/architecture/kindavim-architecture.html' | relative_url }}">KindaVim Integration</a></li>
</ul>
</div>

</div>
