---
layout: default
title: KeyPath for Kanata Users
description: Keep your Kanata config. Let KeyPath handle macOS permissions, services, and reliability.
hide_sidebar: true
content_class: content-full kanata-landing
---

<div class="kanata-landing">
  <section class="kanata-landing-hero">
    <div class="kanata-landing-hero-grid">
      <div>
        <div class="kanata-landing-kicker">
          <span class="kanata-landing-badge">For Kanata users on macOS</span>
          <span>Keep your config. Lose the glue.</span>
        </div>

        <h1 class="kanata-landing-title">KeyPath makes Kanata feel native on macOS.</h1>

        <p class="kanata-landing-subtitle">
          If you already love Kanata, KeyPath is the missing macOS layer: reliable service management,
          guided permissions, driver setup, and fast diagnosis — while preserving your existing <code>.kbd</code>.
        </p>

        <div class="kanata-landing-actions">
          <a class="button button-orange" href="{{ '/migration/kanata-users' | relative_url }}">Migration guide</a>
          <a class="button button-secondary" href="{{ '/getting-started/installation' | relative_url }}">Install KeyPath</a>
          <a class="button button-secondary" href="{{ site.github_url }}/releases">Download releases</a>
        </div>

        <p class="kanata-landing-fineprint mb-0" style="margin-top: 14px;">
          BYOC-friendly: KeyPath does <strong>not</strong> parse or “import” your config into a UI. It runs it.
          Your file stays yours.
        </p>
      </div>

      <div class="kanata-landing-hero-visual">
        <img
          class="kanata-landing-hero-image"
          src="{{ '/images/kanata-landing-hero.png' | relative_url }}"
          alt="KeyPath branding"
          loading="lazy"
        />
      </div>
    </div>
  </section>

  <section class="kanata-landing-section">
    <h2>What you get (without giving up Kanata)</h2>
    <div class="kanata-landing-grid-3">
      <div class="kanata-landing-card">
        <h3>Reliable service management</h3>
        <p>LaunchDaemon setup, restarts, and health checks — without you babysitting <code>launchctl</code>.</p>
      </div>
      <div class="kanata-landing-card">
        <h3>Permissions, handled</h3>
        <p>Guided wizard for Input Monitoring & Accessibility, plus clear “Fix” actions when something breaks.</p>
      </div>
      <div class="kanata-landing-card">
        <h3>Conflict detection & recovery</h3>
        <p>Detects common macOS remapper conflicts and helps you get back to a known-good state fast.</p>
      </div>
    </div>
  </section>

  <section class="kanata-landing-section">
    <h2>Migration in ~3 minutes</h2>
    <div class="kanata-landing-grid-2">
      <div class="kanata-landing-card">
        <h3>1) Put your config where KeyPath expects it</h3>
        <p>Copy (or symlink) your existing Kanata config into KeyPath’s config directory.</p>
        <div class="kanata-landing-code">

```bash
mkdir -p ~/.config/keypath
cp ~/.config/kanata/kanata.kbd ~/.config/keypath/keypath.kbd
```

        </div>
      </div>

      <div class="kanata-landing-card">
        <h3>2) Add one include line</h3>
        <p>KeyPath uses a simple two-file model: you own <code>keypath.kbd</code>; KeyPath owns a generated companion file.</p>
        <div class="kanata-landing-code">

```lisp
(include keypath-apps.kbd)
```

        </div>
        <p class="kanata-landing-fineprint mb-0">
          Full details (including limitations) are in the <a href="{{ '/migration/kanata-users' | relative_url }}">migration guide</a>.
        </p>
      </div>
    </div>
  </section>

  <section class="kanata-landing-section">
    <h2>Built for how Kanata power-users actually work</h2>
    <div class="kanata-landing-grid-3">
      <div class="kanata-landing-card">
        <h3>Bring Your Own Config</h3>
        <p>
          Keep your layers, aliases, macros, and includes. KeyPath preserves your file and avoids risky parsing/import.
        </p>
      </div>
      <div class="kanata-landing-card">
        <h3>Hot reload & diagnostics</h3>
        <p>
          TCP-enabled validation and health checks so you can iterate quickly without losing trust in the system.
        </p>
      </div>
      <div class="kanata-landing-card">
        <h3>Safety features</h3>
        <p>
          Emergency stop, clear system state inspection, and recovery paths when macOS permissions drift.
        </p>
      </div>
    </div>
  </section>

  <section class="kanata-landing-section">
    <h2>Suggested visuals (placeholders)</h2>
    <div class="kanata-landing-grid-2">
      <div class="media-placeholder">
        <div>
          <strong>Screenshot:</strong> Setup Wizard “Fix Issues” screen<br />
          <span class="kanata-landing-fineprint">Shows permission + service repair flow.</span>
        </div>
      </div>
      <div class="media-placeholder">
        <div>
          <strong>Screenshot:</strong> System health / status view<br />
          <span class="kanata-landing-fineprint">Communicates “Kanata is running, TCP ok, conflicts: none”.</span>
        </div>
      </div>
      <div class="media-placeholder">
        <div>
          <strong>GIF/Video:</strong> Edit config → hot reload → remap works<br />
          <span class="kanata-landing-fineprint">Shows fast iteration loop for BYOC users.</span>
        </div>
      </div>
      <div class="media-placeholder">
        <div>
          <strong>Screenshot:</strong> Live overlay / layer indicator (if enabled)<br />
          <span class="kanata-landing-fineprint">Optional “nice UI” that doesn’t require abandoning your config.</span>
        </div>
      </div>
    </div>
  </section>

  <section class="kanata-landing-section">
    <div class="kanata-landing-card">
      <h2 class="mt-0">Ready?</h2>
      <p>
        Start with the migration guide, or install KeyPath and let the wizard do the macOS setup.
      </p>
      <div class="kanata-landing-actions">
        <a class="button button-orange" href="{{ '/migration/kanata-users' | relative_url }}">Read migration guide</a>
        <a class="button button-primary" href="{{ '/getting-started/installation' | relative_url }}">Install KeyPath</a>
        <a class="button button-secondary" href="{{ site.github_url }}/issues">Ask a question</a>
      </div>
    </div>
  </section>
</div>

