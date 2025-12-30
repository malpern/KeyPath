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
        </div>

        <h1 class="kanata-landing-title">Tap. Remap. Done.</h1>

        <p class="kanata-landing-subtitle">
          KeyPath is the macOS layer for Kanata: permissions, LaunchDaemon reliability, and fast diagnosis — while preserving your existing <code>.kbd</code>.
        </p>

        <div class="kanata-landing-actions">
          <a class="button button-orange" href="{{ '/migration/kanata-users' | relative_url }}">Migration guide</a>
          <a class="button button-secondary" href="{{ site.github_url }}/releases">Download</a>
        </div>

        <p class="kanata-landing-fineprint mb-0" style="margin-top: 14px;">
          BYOC-friendly. KeyPath runs your config; it doesn’t parse or “import” it into a UI.
        </p>
      </div>

      <div class="kanata-landing-hero-visual">
        <img
          class="kanata-landing-hero-image"
          src="{{ '/images/keypath-hero-nobg.png' | relative_url }}"
          alt="KeyPath"
          loading="lazy"
        />
      </div>
    </div>
  </section>

  <section class="kanata-landing-section">
    <div class="kanata-landing-simple">
      <h2 class="mt-0">Why KeyPath?</h2>
      <ul class="kanata-landing-bullets">
        <li><strong>Permissions, handled.</strong> Guided setup for Input Monitoring & Accessibility.</li>
        <li><strong>Reliable service.</strong> LaunchDaemon install + restart + health checks.</li>
        <li><strong>Keep Kanata.</strong> Your <code>.kbd</code> stays yours (BYOC).</li>
      </ul>
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
    <div class="kanata-landing-card">
      <h2 class="mt-0">Ready?</h2>
      <p>Start with the migration guide.</p>
      <div class="kanata-landing-actions">
        <a class="button button-orange" href="{{ '/migration/kanata-users' | relative_url }}">Read migration guide</a>
        <a class="button button-secondary" href="{{ site.github_url }}/issues">Ask a question</a>
      </div>
    </div>
  </section>
</div>

