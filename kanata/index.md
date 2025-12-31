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
          Already using Kanata? Drop in your existing <code>.kbd</code> and keep working. <a href="{{ '/migration/kanata-users' | relative_url }}">Tips for existing Kanata users</a>.
        </p>

        <div class="kanata-landing-actions">
          <a class="button button-orange" href="https://github.com/malpern/KeyPath/releases/download/v1.0.0/KeyPath-1.0.0.zip">Download</a>
          <a class="button button-secondary" href="https://github.com/malpern/KeyPath/releases/tag/v1.0.0">Release notes</a>
        </div>

        <p class="kanata-landing-fineprint mb-0" style="margin-top: 14px;">
          <a href="{{ '/migration/kanata-users' | relative_url }}">Easily use an existing config.kbd</a>
        </p>

        <p class="kanata-landing-fineprint mb-0" style="margin-top: 12px;">
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
<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" xmlns="http://www.w3.org/2000/svg" class="kp-icon"><path d="M12 2v10" /><path d="M18.4 6.6a9 9 0 1 1-12.77.04" /></svg>
        </span>
        <div class="kanata-feature-text">
          <div class="kanata-feature-title">Advanced key remapping powered by Kanata</div>
          <div class="kanata-feature-body">Keymaps, layers, sequences, chords, macros — the good stuff.</div>
        </div>
      </li>

      <li class="kanata-feature kp-accent-purple">
        <span class="kanata-feature-icon" aria-hidden="true">
<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" xmlns="http://www.w3.org/2000/svg" class="kp-icon"><rect x="2" y="4" width="20" height="16" rx="2" /><path d="M10 4v4" /><path d="M2 8h20" /><path d="M6 4v4" /></svg>
        </span>
        <div class="kanata-feature-text">
          <div class="kanata-feature-title">App launcher</div>
          <div class="kanata-feature-body">Open apps with a key, layer, or shortcut.</div>
        </div>
      </li>

      <li class="kanata-feature kp-accent-green">
        <span class="kanata-feature-icon" aria-hidden="true">
<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" xmlns="http://www.w3.org/2000/svg" class="kp-icon"><rect width="18" height="18" x="3" y="3" rx="2" /><path d="M3 9h18" /><path d="M9 21V9" /></svg>
        </span>
        <div class="kanata-feature-text">
          <div class="kanata-feature-title">Window tools</div>
          <div class="kanata-feature-body">Snap, move, and resize with consistent shortcuts.</div>
        </div>
      </li>

      <li class="kanata-feature kp-accent-orange">
        <span class="kanata-feature-icon" aria-hidden="true">
<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" xmlns="http://www.w3.org/2000/svg" class="kp-icon"><path d="M10 8h.01" /><path d="M12 12h.01" /><path d="M14 8h.01" /><path d="M16 12h.01" /><path d="M18 8h.01" /><path d="M6 8h.01" /><path d="M7 16h10" /><path d="M8 12h.01" /><rect width="20" height="16" x="2" y="4" rx="2" /></svg>
        </span>
        <div class="kanata-feature-text">
          <div class="kanata-feature-title">Home-row mods</div>
          <div class="kanata-feature-body">Tap-hold, layers, macros, and combos.</div>
        </div>
      </li>

      <li class="kanata-feature kp-accent-slate">
        <span class="kanata-feature-icon" aria-hidden="true">
<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" xmlns="http://www.w3.org/2000/svg" class="kp-icon"><path d="M6 22a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h8a2.4 2.4 0 0 1 1.704.706l3.588 3.588A2.4 2.4 0 0 1 20 8v12a2 2 0 0 1-2 2z" /><path d="M14 2v5a1 1 0 0 0 1 1h5" /><path d="M10 9H8" /><path d="M16 13H8" /><path d="M16 17H8" /></svg>
        </span>
        <div class="kanata-feature-text">
          <div class="kanata-feature-title">Bring your config</div>
          <div class="kanata-feature-body">Keep your existing Kanata <code>.kbd</code>. <a href="{{ '/migration/kanata-users' | relative_url }}">Tips for existing Kanata users</a>.</div>
        </div>
      </li>

      <li class="kanata-feature kp-accent-teal">
        <span class="kanata-feature-icon" aria-hidden="true">
<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" xmlns="http://www.w3.org/2000/svg" class="kp-icon"><path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z" /><path d="m9 12 2 2 4-4" /></svg>
        </span>
        <div class="kanata-feature-text">
          <div class="kanata-feature-title">Guided setup</div>
          <div class="kanata-feature-body">Input Monitoring + Accessibility, step-by-step.</div>
        </div>
      </li>
    </ul>
  
</section>

  <section class="kanata-landing-section">
    <h2 class="mt-0">Launch apps & websites</h2>
    <p class="kanata-landing-fineprint mb-0">
      Turn “go to X” into muscle memory: one key can open an app, a URL, or a workflow.
    </p>

    <div class="kanata-landing-grid-2 kanata-launches">
      <div class="kanata-landing-simple">
        <ul class="kanata-landing-bullets">
          <li><strong>Apps:</strong> bind Safari, Finder, Slack, etc.</li>
          <li><strong>Websites:</strong> open docs, dashboards, PRs, and tickets.</li>
          <li><strong>Fast:</strong> trigger from a key, layer, chord, or sequence.</li>
        </ul>
      </div>

      <div class="kanata-launches-media">
        <img
          class="kanata-launches-image"
          src="{{ '/images/kanata-launcher.png' | relative_url }}"
          alt="KeyPath launcher mapping apps and websites"
          loading="lazy"
        />
      </div>
    </div>

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
          Full details (including limitations) are in the <a href="{{ '/migration/kanata-users' | relative_url }}">Tips for existing Kanata users</a>.
        </p>
      </div>
    </div>
  </section>

  <div class="kanata-landing-divider" aria-hidden="true"></div>

  <section class="kanata-landing-section">
    <h2 class="mt-0">Ready?</h2>
    <p>Start with the Tips for existing Kanata users.</p>
    <div class="kanata-landing-actions">
      <a class="button button-orange" href="{{ '/migration/kanata-users' | relative_url }}">Use existing config</a>
      <a class="button button-secondary" href="{{ site.github_url }}/issues">Ask a question</a>
    </div>
  </section>
</div>

