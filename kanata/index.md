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

        <h1 class="kanata-landing-title">KeyPath</h1>

        <p class="kanata-landing-subtitle">
          Tap. Remap. Done.
        </p>

        <p>
          Simple keyboard remapping on macOS: guided setup, a reliable background service, and quick fixes when something breaks.
          Already using Kanata? Drop in your existing <code>.kbd</code> and keep working.
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
    <h2 class="mt-0">Why KeyPath?</h2>
    <p class="kanata-landing-fineprint mb-0">
      Everything you love about Kanata — with Mac ease-of-use and extra power built in.
    </p>
    <ul class="kanata-feature-list">
      <li class="kanata-feature kp-accent-blue">
        <span class="kanata-feature-icon" aria-hidden="true">
          <svg viewBox="0 0 24 24" class="kp-icon" fill="none">
            <path d="M7 7h6V4l4 4-4 4V9H7c-2.2 0-4 1.8-4 4 0 1 .4 1.9 1 2.6" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>
            <path d="M17 17H11v3l-4-4 4-4v3h6c2.2 0 4-1.8 4-4 0-1-.4-1.9-1-2.6" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>
          </svg>
        </span>
        <div class="kanata-feature-text">
          <div class="kanata-feature-title">Always-on</div>
          <div class="kanata-feature-body">Starts at boot and restarts if it crashes.</div>
        </div>
      </li>

      <li class="kanata-feature kp-accent-purple">
        <span class="kanata-feature-icon" aria-hidden="true">
          <svg viewBox="0 0 24 24" class="kp-icon" fill="none">
            <path d="M10 14a6 6 0 1 1 4 0" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>
            <path d="M12 2v6" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>
            <path d="M10 22l2-4 2 4" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>
          </svg>
        </span>
        <div class="kanata-feature-text">
          <div class="kanata-feature-title">App launcher</div>
          <div class="kanata-feature-body">Open apps with a key, layer, or shortcut.</div>
        </div>
      </li>

      <li class="kanata-feature kp-accent-green">
        <span class="kanata-feature-icon" aria-hidden="true">
          <svg viewBox="0 0 24 24" class="kp-icon" fill="none">
            <rect x="4" y="5" width="16" height="14" rx="2.5" stroke="currentColor" stroke-width="1.8"/>
            <path d="M12 5v14" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>
          </svg>
        </span>
        <div class="kanata-feature-text">
          <div class="kanata-feature-title">Window tools</div>
          <div class="kanata-feature-body">Snap, move, and resize with consistent shortcuts.</div>
        </div>
      </li>

      <li class="kanata-feature kp-accent-orange">
        <span class="kanata-feature-icon" aria-hidden="true">
          <svg viewBox="0 0 24 24" class="kp-icon" fill="none">
            <rect x="3" y="7" width="18" height="11" rx="2.5" stroke="currentColor" stroke-width="1.8"/>
            <path d="M7 11h1M10 11h1M13 11h1M16 11h1M7 14h10" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>
          </svg>
        </span>
        <div class="kanata-feature-text">
          <div class="kanata-feature-title">Home-row mods</div>
          <div class="kanata-feature-body">Tap-hold, layers, macros, and combos.</div>
        </div>
      </li>

      <li class="kanata-feature kp-accent-slate">
        <span class="kanata-feature-icon" aria-hidden="true">
          <svg viewBox="0 0 24 24" class="kp-icon" fill="none">
            <path d="M8 4h6l2 2v14H8V4z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/>
            <path d="M14 4v3h3" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>
            <path d="M10 12h6M10 15h6" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>
          </svg>
        </span>
        <div class="kanata-feature-text">
          <div class="kanata-feature-title">Bring your config</div>
          <div class="kanata-feature-body">Keep your existing Kanata <code>.kbd</code>.</div>
        </div>
      </li>

      <li class="kanata-feature kp-accent-teal">
        <span class="kanata-feature-icon" aria-hidden="true">
          <svg viewBox="0 0 24 24" class="kp-icon" fill="none">
            <path d="M12 2l8 4v6c0 5-3.2 9.4-8 10-4.8-.6-8-5-8-10V6l8-4z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/>
            <path d="M8.5 12.2l2.2 2.2 4.8-5" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>
          </svg>
        </span>
        <div class="kanata-feature-text">
          <div class="kanata-feature-title">Guided setup</div>
          <div class="kanata-feature-body">Input Monitoring + Accessibility, step-by-step.</div>
        </div>
      </li>
    </ul>
  </section>

  <div class="kanata-landing-divider" aria-hidden="true"></div>

  <section class="kanata-landing-section">
    <h2>Use your existing Kanata config</h2>
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
          Full details (including limitations) are in the <a href="{{ '/migration/kanata-users' | relative_url }}">existing config guide</a>.
        </p>
      </div>
    </div>
  </section>

  <div class="kanata-landing-divider" aria-hidden="true"></div>

  <section class="kanata-landing-section">
    <h2 class="mt-0">Ready?</h2>
    <p>Start with the existing config guide.</p>
    <div class="kanata-landing-actions">
      <a class="button button-orange" href="{{ '/migration/kanata-users' | relative_url }}">Use existing config</a>
      <a class="button button-secondary" href="{{ site.github_url }}/issues">Ask a question</a>
    </div>
  </section>
</div>

