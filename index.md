---
layout: default
title: KeyPath - The Native Mac Keyboard Power Tool
description: Keep your Kanata config. Let KeyPath handle macOS permissions, services, and reliability.
hide_sidebar: true
content_class: content-full kanata-landing
---

<div class="kanata-landing">
  <!-- HERO: Full-screen impact with progressive reveal -->
  <section class="kanata-landing-hero">
    <!-- Breathing glow effect -->
    <div class="kanata-landing-hero-glow" aria-hidden="true"></div>

    <div class="kanata-landing-hero-content">
      <h1 class="kanata-landing-title hero-animate hero-animate-1">KeyPath</h1>
      <p class="kanata-landing-tagline hero-animate hero-animate-2">Turn your keyboard into a command center</p>
      <p class="kanata-landing-subtitle hero-animate hero-animate-3">Remap keys, launch apps, tile windows, and automate workflows — all without leaving the home row.</p>

      <div class="kanata-landing-actions hero-animate hero-animate-4">
        <a class="button button-orange" href="https://github.com/malpern/KeyPath/releases/download/v1.0.0/KeyPath-1.0.0.zip">Download for macOS <span class="button-badge">Free</span></a>
      </div>

      <p class="kanata-landing-requirements hero-animate hero-animate-5">Requires macOS 15+ (Sequoia) · Apple Silicon</p>
    </div>

    <!-- App screenshot -->
    <div class="kanata-landing-hero-visual">
      <img
        class="kanata-landing-hero-image"
        src="{{ '/images/keypath-hero-nobg.png' | relative_url }}"
        alt="KeyPath app showing keyboard visualization with layers"
        loading="eager"
      />
    </div>
  </section>

  <!-- DEMO VIDEO SECTION -->
  <section class="kanata-landing-video-section">
    <div class="kanata-landing-video-container">
      <div class="kanata-landing-video-placeholder">
        <div class="kanata-landing-video-icon">
          <svg viewBox="0 0 24 24" fill="currentColor" width="64" height="64">
            <path d="M8 5v14l11-7z"/>
          </svg>
        </div>
        <p class="kanata-landing-video-label">Demo video coming soon</p>
      </div>
    </div>
  </section>

  <!-- LAUNCH ANYTHING SECTION - Cinematic Demo -->
  <section class="launch-cinema">
    <h2 class="cinema-title">Launch anything with muscle memory</h2>
    <p class="cinema-subtitle">
      Turn "go to X" into muscle memory: any gesture can open an app, a URL, or a workflow.
    </p>

    <ul class="cinema-features">
      <li><strong>Apps:</strong> bind Safari, Finder, Slack, etc.</li>
      <li><strong>Websites:</strong> open docs, dashboards, PRs, and tickets.</li>
      <li><strong>Fast:</strong> trigger from a key, layer, chord, or sequence.</li>
    </ul>

    <div class="cinema-spacer"></div>

    <div class="launch-cinema-stage">
      <!-- Gesture label (typed in) -->
      <div class="cinema-gesture">
        <span class="cinema-gesture-text"></span>
        <span class="cinema-cursor">|</span>
      </div>

      <!-- Keys display -->
      <div class="cinema-keys"></div>

      <!-- Result (app icon + name) -->
      <div class="cinema-result">
        <div class="cinema-app-icon"></div>
        <div class="cinema-app-name"></div>
      </div>

      <!-- Summary slide -->
      <div class="cinema-summary">
        <h3 class="cinema-summary-title">Five ways to trigger anything</h3>
        <div class="cinema-summary-grid">
          <div class="cinema-summary-item" data-summary="0">
            <div class="cinema-summary-icon slack"></div>
            <span class="cinema-summary-label">Two keys<br>at once</span>
          </div>
          <div class="cinema-summary-item" data-summary="1">
            <div class="cinema-summary-icon github"></div>
            <span class="cinema-summary-label">Keys in<br>a row</span>
          </div>
          <div class="cinema-summary-item" data-summary="2">
            <div class="cinema-summary-icon figma"></div>
            <span class="cinema-summary-label">Double-tap</span>
          </div>
          <div class="cinema-summary-item" data-summary="3">
            <div class="cinema-summary-icon safari"></div>
            <span class="cinema-summary-label">Hold + tap</span>
          </div>
          <div class="cinema-summary-item" data-summary="4">
            <div class="cinema-summary-icon docs"></div>
            <span class="cinema-summary-label">Tap, then<br>type</span>
          </div>
        </div>
        <button class="cinema-replay-btn">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M1 4v6h6"/><path d="M3.51 15a9 9 0 1 0 2.13-9.36L1 10"/></svg>
          Play again
        </button>
      </div>
    </div>

    <!-- Progress dots -->
    <div class="cinema-progress">
      <span class="cinema-dot active" data-index="0"></span>
      <span class="cinema-dot" data-index="1"></span>
      <span class="cinema-dot" data-index="2"></span>
      <span class="cinema-dot" data-index="3"></span>
      <span class="cinema-dot" data-index="4"></span>
      <span class="cinema-dot" data-index="5"></span>
    </div>
  </section>

  <!-- BUILD YOUR OWN RULES - Full Screen -->
  <section class="rules-fullscreen">
    <div class="rules-fullscreen-content">
      <h2 class="rules-fullscreen-title">Pre-built rules included</h2>
      <p class="rules-fullscreen-subtitle">Enable popular keyboard power moves with one click</p>

      <div class="rules-chips-grid">
        <div class="rule-chip-large">
          <div class="rule-chip-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="11" width="18" height="10" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>
          </div>
          <div class="rule-chip-text">
            <span class="rule-chip-name">Caps Lock Remap</span>
            <span class="rule-chip-desc">Escape on tap, Hyper on hold</span>
          </div>
        </div>

        <div class="rule-chip-large">
          <div class="rule-chip-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="6" width="20" height="12" rx="2"/><path d="M6 10h.01M10 10h.01M14 10h.01M18 10h.01"/></svg>
          </div>
          <div class="rule-chip-text">
            <span class="rule-chip-name">Home Row Mods</span>
            <span class="rule-chip-desc">Ctrl, Alt, Cmd, Shift under your fingers</span>
          </div>
        </div>

        <div class="rule-chip-large">
          <div class="rule-chip-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M5 12h14M12 5l7 7-7 7"/></svg>
          </div>
          <div class="rule-chip-text">
            <span class="rule-chip-name">Vim Navigation</span>
            <span class="rule-chip-desc">HJKL as arrow keys everywhere</span>
          </div>
        </div>

        <div class="rule-chip-large">
          <div class="rule-chip-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/></svg>
          </div>
          <div class="rule-chip-text">
            <span class="rule-chip-name">Window Snapping</span>
            <span class="rule-chip-desc">Tile windows with keyboard shortcuts</span>
          </div>
        </div>

        <div class="rule-chip-large">
          <div class="rule-chip-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="3"/><path d="M12 2v4M12 18v4M2 12h4M18 12h4"/></svg>
          </div>
          <div class="rule-chip-text">
            <span class="rule-chip-name">Quick Launcher</span>
            <span class="rule-chip-desc">Open apps and URLs with hotkeys</span>
          </div>
        </div>

        <div class="rule-chip-large">
          <div class="rule-chip-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5"/></svg>
          </div>
          <div class="rule-chip-text">
            <span class="rule-chip-name">Symbol Layer</span>
            <span class="rule-chip-desc">Access symbols without Shift</span>
          </div>
        </div>
      </div>

      <p class="rules-fullscreen-note">
        Or build your own — KeyPath supports all Kanata features
      </p>
    </div>
  </section>

  <div class="kanata-landing-divider" aria-hidden="true"></div>

  <!-- ALTERNATE LAYOUTS - Full Screen -->
  <section class="layouts-fullscreen">
    <div class="layouts-fullscreen-content">
      <h2 class="layouts-fullscreen-title">Explore alternate keyboard layouts</h2>
      <p class="layouts-fullscreen-subtitle">Switch layouts instantly — no firmware flashing required</p>

      <video class="layouts-video" autoplay loop muted playsinline preload="auto" poster="{{ '/images/alt-layouts-poster.jpg' | relative_url }}">
        <source src="{{ '/images/alt-layouts.mp4' | relative_url }}" type="video/mp4">
        <source src="{{ '/images/alt-layouts.mov' | relative_url }}" type="video/quicktime">
      </video>

      <p class="layouts-hint">Hover to learn more</p>
      <div class="layouts-grid">
        <div class="layout-flip-card">
          <div class="layout-flip-inner">
            <div class="layout-flip-front">
              <div class="layout-card-name">Colemak</div>
              <div class="layout-card-type">Popular</div>
            </div>
            <div class="layout-flip-back">
              <p><strong>74%</strong> of typing on home row vs QWERTY's 32%</p>
              <a href="https://colemak.com/" target="_blank" rel="noopener" class="layout-info-link" title="Learn more about Colemak">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="layout-info-icon"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/></svg>
              </a>
            </div>
          </div>
        </div>
        <div class="layout-flip-card">
          <div class="layout-flip-inner">
            <div class="layout-flip-front">
              <div class="layout-card-name">Colemak-DH</div>
              <div class="layout-card-type">Modern</div>
            </div>
            <div class="layout-flip-back">
              <p><strong>46%</strong> less finger travel than QWERTY</p>
              <a href="https://colemakmods.github.io/mod-dh/" target="_blank" rel="noopener" class="layout-info-link" title="Learn more about Colemak-DH">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="layout-info-icon"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/></svg>
              </a>
            </div>
          </div>
        </div>
        <div class="layout-flip-card">
          <div class="layout-flip-inner">
            <div class="layout-flip-front">
              <div class="layout-card-name">Dvorak</div>
              <div class="layout-card-type">Classic</div>
            </div>
            <div class="layout-flip-back">
              <p>Since <strong>1936</strong> — the original alternative layout</p>
              <a href="https://en.wikipedia.org/wiki/Dvorak_keyboard_layout" target="_blank" rel="noopener" class="layout-info-link" title="Learn more about Dvorak">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="layout-info-icon"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/></svg>
              </a>
            </div>
          </div>
        </div>
        <div class="layout-flip-card">
          <div class="layout-flip-inner">
            <div class="layout-flip-front">
              <div class="layout-card-name">Workman</div>
              <div class="layout-card-type">Ergonomic</div>
            </div>
            <div class="layout-flip-back">
              <p>Optimized for <strong>inward rolls</strong> — the most comfortable motion</p>
              <a href="https://workmanlayout.org/" target="_blank" rel="noopener" class="layout-info-link" title="Learn more about Workman">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="layout-info-icon"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/></svg>
              </a>
            </div>
          </div>
        </div>
        <div class="layout-flip-card">
          <div class="layout-flip-inner">
            <div class="layout-flip-front">
              <div class="layout-card-name">Graphite</div>
              <div class="layout-card-type">Newest</div>
            </div>
            <div class="layout-flip-back">
              <p><strong>65%</strong> home row usage with balanced hands</p>
              <a href="https://github.com/rdavison/graphite-layout" target="_blank" rel="noopener" class="layout-info-link" title="Learn more about Graphite">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="layout-info-icon"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/></svg>
              </a>
            </div>
          </div>
        </div>
      </div>

      <p class="layouts-international">
        Plus AZERTY, QWERTZ, JIS, and international variants
      </p>
    </div>
  </section>

  <div class="kanata-landing-divider" aria-hidden="true"></div>

  <!-- WORKS WITH YOUR KEYBOARD - Full Screen -->
  <section class="keyboards-fullscreen">
    <div class="keyboards-fullscreen-content">
      <h2 class="keyboards-fullscreen-title">Works with your keyboard</h2>
      <p class="keyboards-fullscreen-subtitle">From MacBook to mechanical split — no firmware flashing required</p>
    </div>

    <div class="keyboard-marquee">
      <div class="keyboard-marquee-track">
        <div class="keyboard-marquee-item" data-stat="Auto-detected on first launch">
          <img src="{{ '/images/keyboards/web-macbook-us.png' | relative_url }}" alt="MacBook keyboard" class="keyboard-marquee-img">
          <div class="keyboard-marquee-name">MacBook</div>
        </div>
        <div class="keyboard-marquee-item" data-stat="Most popular compact size">
          <img src="{{ '/images/keyboards/web-60-percent.png' | relative_url }}" alt="60% keyboard" class="keyboard-marquee-img">
          <div class="keyboard-marquee-name">60%</div>
        </div>
        <div class="keyboard-marquee-item" data-stat="Arrows without the bulk">
          <img src="{{ '/images/keyboards/web-65-percent-a.png' | relative_url }}" alt="65% keyboard" class="keyboard-marquee-img">
          <div class="keyboard-marquee-name">65%</div>
        </div>
        <div class="keyboard-marquee-item" data-stat="Function row, no numpad">
          <img src="{{ '/images/keyboards/web-75-percent-a.png' | relative_url }}" alt="75% keyboard" class="keyboard-marquee-img">
          <div class="keyboard-marquee-name">75%</div>
        </div>
        <div class="keyboard-marquee-item" data-stat="The classic tenkeyless">
          <img src="{{ '/images/keyboards/web-tkl-80.png' | relative_url }}" alt="TKL keyboard" class="keyboard-marquee-img">
          <div class="keyboard-marquee-name">TKL</div>
        </div>
        <div class="keyboard-marquee-item" data-stat="All 104 keys">
          <img src="{{ '/images/keyboards/web-full-size.png' | relative_url }}" alt="Full-size keyboard" class="keyboard-marquee-img">
          <div class="keyboard-marquee-name">Full-size</div>
        </div>
        <div class="keyboard-marquee-item" data-stat="42 keys of pure efficiency">
          <img src="{{ '/images/keyboards/web-corne-split-a.png' | relative_url }}" alt="Corne keyboard" class="keyboard-marquee-img">
          <div class="keyboard-marquee-name">Corne</div>
        </div>
        <div class="keyboard-marquee-item" data-stat="34 keys, no compromises">
          <img src="{{ '/images/keyboards/web-sweep-split-a.png' | relative_url }}" alt="Ferris Sweep keyboard" class="keyboard-marquee-img">
          <div class="keyboard-marquee-name">Ferris Sweep</div>
        </div>
        <div class="keyboard-marquee-item" data-stat="The ergo endgame">
          <img src="{{ '/images/keyboards/web-kinesis-advantage.png' | relative_url }}" alt="Kinesis keyboard" class="keyboard-marquee-img">
          <div class="keyboard-marquee-name">Kinesis</div>
        </div>
        <!-- Duplicate for seamless loop -->
        <div class="keyboard-marquee-item" data-stat="Auto-detected on first launch">
          <img src="{{ '/images/keyboards/web-macbook-us.png' | relative_url }}" alt="MacBook keyboard" class="keyboard-marquee-img">
          <div class="keyboard-marquee-name">MacBook</div>
        </div>
        <div class="keyboard-marquee-item" data-stat="Most popular compact size">
          <img src="{{ '/images/keyboards/web-60-percent.png' | relative_url }}" alt="60% keyboard" class="keyboard-marquee-img">
          <div class="keyboard-marquee-name">60%</div>
        </div>
        <div class="keyboard-marquee-item" data-stat="Arrows without the bulk">
          <img src="{{ '/images/keyboards/web-65-percent-a.png' | relative_url }}" alt="65% keyboard" class="keyboard-marquee-img">
          <div class="keyboard-marquee-name">65%</div>
        </div>
        <div class="keyboard-marquee-item" data-stat="Function row, no numpad">
          <img src="{{ '/images/keyboards/web-75-percent-a.png' | relative_url }}" alt="75% keyboard" class="keyboard-marquee-img">
          <div class="keyboard-marquee-name">75%</div>
        </div>
        <div class="keyboard-marquee-item" data-stat="The classic tenkeyless">
          <img src="{{ '/images/keyboards/web-tkl-80.png' | relative_url }}" alt="TKL keyboard" class="keyboard-marquee-img">
          <div class="keyboard-marquee-name">TKL</div>
        </div>
        <div class="keyboard-marquee-item" data-stat="All 104 keys">
          <img src="{{ '/images/keyboards/web-full-size.png' | relative_url }}" alt="Full-size keyboard" class="keyboard-marquee-img">
          <div class="keyboard-marquee-name">Full-size</div>
        </div>
        <div class="keyboard-marquee-item" data-stat="42 keys of pure efficiency">
          <img src="{{ '/images/keyboards/web-corne-split-a.png' | relative_url }}" alt="Corne keyboard" class="keyboard-marquee-img">
          <div class="keyboard-marquee-name">Corne</div>
        </div>
        <div class="keyboard-marquee-item" data-stat="34 keys, no compromises">
          <img src="{{ '/images/keyboards/web-sweep-split-a.png' | relative_url }}" alt="Ferris Sweep keyboard" class="keyboard-marquee-img">
          <div class="keyboard-marquee-name">Ferris Sweep</div>
        </div>
        <div class="keyboard-marquee-item" data-stat="The ergo endgame">
          <img src="{{ '/images/keyboards/web-kinesis-advantage.png' | relative_url }}" alt="Kinesis keyboard" class="keyboard-marquee-img">
          <div class="keyboard-marquee-name">Kinesis</div>
        </div>
      </div>
    </div>
  </section>

  <div class="kanata-landing-divider" aria-hidden="true"></div>

  <!-- Home Row Mods Section -->
  <section class="hrm-section">
    <div class="hrm-header">
      <h2>Home Row Mods</h2>
      <p class="hrm-subtitle">The keyboard upgrade you didn't know you needed</p>
    </div>

    <div class="hrm-content">
      <div class="hrm-demo">
        <!-- Output display showing what's being typed -->
        <div class="hrm-output">
          <span class="hrm-output-badge">Shortcut</span>
          <span class="hrm-output-text"></span>
          <span class="hrm-output-cursor">|</span>
        </div>

        <div class="hrm-keyboard">
          <div class="hrm-row hrm-row-home">
            <div class="hrm-key hrm-key-mod" data-key="a" data-mod="Ctrl">
              <span class="hrm-key-letter">A</span>
              <span class="hrm-key-mod-label">Ctrl</span>
            </div>
            <div class="hrm-key hrm-key-mod" data-key="s" data-mod="Alt">
              <span class="hrm-key-letter">S</span>
              <span class="hrm-key-mod-label">Alt</span>
            </div>
            <div class="hrm-key hrm-key-mod" data-key="d" data-mod="Cmd">
              <span class="hrm-key-letter">D</span>
              <span class="hrm-key-mod-label">⌘</span>
            </div>
            <div class="hrm-key hrm-key-mod" data-key="f" data-mod="Shift">
              <span class="hrm-key-letter">F</span>
              <span class="hrm-key-mod-label">⇧</span>
            </div>
          </div>
        </div>

        <div class="hrm-demo-label">
          <span class="hrm-demo-mode"></span>
        </div>
      </div>

      <div class="hrm-explanation">
        <div class="hrm-benefit">
          <div class="hrm-benefit-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22c5.523 0 10-4.477 10-10S17.523 2 12 2 2 6.477 2 12s4.477 10 10 10z"/><path d="m9 12 2 2 4-4"/></svg>
          </div>
          <div class="hrm-benefit-text">
            <h4>No more reaching</h4>
            <p>Ctrl, Alt, Cmd, and Shift live right under your fingers. No stretching to the corners of your keyboard.</p>
          </div>
        </div>

        <div class="hrm-benefit">
          <div class="hrm-benefit-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M13 2 3 14h9l-1 8 10-12h-9l1-8z"/></svg>
          </div>
          <div class="hrm-benefit-text">
            <h4>Faster shortcuts</h4>
            <p>⌘+S becomes D+S. ⌘+C becomes D+C. Your fingers barely move.</p>
          </div>
        </div>

        <div class="hrm-benefit">
          <div class="hrm-benefit-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"/></svg>
          </div>
          <div class="hrm-benefit-text">
            <h4>Happier hands</h4>
            <p>Less strain, less fatigue. Home row mods are a game-changer for heavy keyboard users.</p>
          </div>
        </div>
      </div>
    </div>

    <div class="hrm-comparison">
      <h3>Why KeyPath does this better</h3>
      <p class="hrm-comparison-intro">Home row mods need precise timing to feel right. Kanata's tap-hold algorithm is the best on Mac.</p>

      <div class="hrm-comparison-grid">
        <div class="hrm-compare-card hrm-compare-others">
          <div class="hrm-compare-header">
            <span class="hrm-compare-label">Karabiner-Elements</span>
          </div>
          <ul class="hrm-compare-list">
            <li class="hrm-compare-con">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 6 6 18M6 6l12 12"/></svg>
              Basic tap-hold only
            </li>
            <li class="hrm-compare-con">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 6 6 18M6 6l12 12"/></svg>
              Accidental triggers when typing fast
            </li>
            <li class="hrm-compare-con">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 6 6 18M6 6l12 12"/></svg>
              Global timing only — can't tune per-key
            </li>
            <li class="hrm-compare-con">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 6 6 18M6 6l12 12"/></svg>
              No bilateral combination support
            </li>
          </ul>
        </div>

        <div class="hrm-compare-card hrm-compare-keypath">
          <div class="hrm-compare-header">
            <span class="hrm-compare-label">KeyPath</span>
            <span class="hrm-compare-badge">Powered by Kanata</span>
          </div>
          <ul class="hrm-compare-list">
            <li class="hrm-compare-pro hrm-has-tooltip">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M20 6 9 17l-5-5"/></svg>
              <span class="hrm-tooltip-trigger">Multiple tap-hold modes</span>
              <span class="hrm-tooltip">Choose the behavior that matches how you type. Some people tap fast, others hold longer — KeyPath adapts to your style.</span>
            </li>
            <li class="hrm-compare-pro hrm-has-tooltip">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M20 6 9 17l-5-5"/></svg>
              <span class="hrm-tooltip-trigger">Smart misfire prevention</span>
              <span class="hrm-tooltip">Type "as" fast and it just types "as" — not Ctrl+S. KeyPath is smart about the difference between fast typing and intentional shortcuts.</span>
            </li>
            <li class="hrm-compare-pro hrm-has-tooltip">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M20 6 9 17l-5-5"/></svg>
              <span class="hrm-tooltip-trigger">Tune each key individually</span>
              <span class="hrm-tooltip">Your pinky moves slower than your index finger. Set different timing for each key so they all feel just right.</span>
            </li>
            <li class="hrm-compare-pro hrm-has-tooltip">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M20 6 9 17l-5-5"/></svg>
              <span class="hrm-tooltip-trigger">Same-hand typing works perfectly</span>
              <span class="hrm-tooltip">Want Ctrl+Shift? Use keys from both hands. Just typing letters? Same-hand combos stay as letters. Almost zero accidental triggers.</span>
            </li>
          </ul>
        </div>
      </div>

      <p class="hrm-cta-text">
        Home row mods used to require custom keyboard firmware. Now you can have them on any Mac keyboard —
        including your MacBook's built-in keyboard.
        <a href="https://precondition.github.io/home-row-mods" target="_blank" rel="noopener" class="hrm-learn-more">
          <svg class="hrm-learn-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M12 6.042A8.967 8.967 0 0 0 6 3.75c-1.052 0-2.062.18-3 .512v14.25A8.987 8.987 0 0 1 6 18c2.305 0 4.408.867 6 2.292m0-14.25a8.966 8.966 0 0 1 6-2.292c1.052 0 2.062.18 3 .512v14.25A8.987 8.987 0 0 0 18 18a8.967 8.967 0 0 0-6 2.292m0-14.25v14.25"/></svg>
          A guide to home row mods
        </a>
      </p>
    </div>
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
          Full details (including limitations) are in <a href="{{ '/migration/kanata-users' | relative_url }}">Tips for existing Kanata users</a>.
        </p>
      </div>
    </div>
  </section>

  <!-- How It Works Section -->
  <section class="explained-section">
    <div class="explained-header">
      <h2>How It Works</h2>
      <p class="subtitle">Kanata transforms simple keypresses into powerful actions.</p>

      <!-- Hidden toggle - revealed by easter egg (press 'p' twice) -->
      <div class="viz-toggle viz-toggle-hidden" role="tablist" aria-label="Visualization style" aria-hidden="true">
        <button class="viz-toggle-btn active" role="tab" aria-selected="true" data-viz-target="timeline">
          Timeline
        </button>
        <button class="viz-toggle-btn" role="tab" aria-selected="false" data-viz-target="piano-roll">
          Piano Roll
        </button>
      </div>
    </div>

  <!-- Timeline Visualization -->
  <div class="viz-panel active" id="viz-timeline" role="tabpanel">
    <div class="kanata-grid">
      <!-- 1. Chords -->
      <div class="kanata-card" data-viz="chord">
        <div class="card-text">
          <h3>Chords</h3>
          <p>Press multiple keys simultaneously</p>
        </div>
        <div class="kanata-viz">
          <div class="track">
            <div class="block block--blue block--chord-1">J</div>
            <div class="block block--purple block--chord-2">K</div>
            <div class="block block--green chord-result">Escape</div>
          </div>
        </div>
      </div>

      <!-- 2. Layers -->
      <div class="kanata-card" data-viz="layers">
        <div class="card-text">
          <h3>Layers</h3>
          <p>Switch between different key layouts</p>
        </div>
        <div class="kanata-viz">
          <div class="multi-track">
            <div class="track-row layer-0">
              <span class="track-label">Base</span>
              <div class="track">
                <div class="block block--orange block--switch">NAV</div>
              </div>
            </div>
            <div class="track-row layer-1">
              <span class="track-label">Nav</span>
              <div class="track">
                <div class="block block--blue nav-key nav-1">←</div>
                <div class="block block--blue nav-key nav-2">↓</div>
                <div class="block block--blue nav-key nav-3">→</div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- 3. Tap-Hold -->
      <div class="kanata-card" data-viz="tap-hold">
        <div class="card-text">
          <h3>Tap-Hold</h3>
          <p>Tap for one key, hold for another</p>
        </div>
        <div class="kanata-viz">
          <div class="track" style="margin-bottom: 12px;">
            <div class="block block--blue tap-block">Esc</div>
            <div class="threshold-line"><span>200ms</span></div>
          </div>
          <div class="track">
            <div class="block block--hold hold-block">Hyper</div>
            <div class="threshold-line"><span>200ms</span></div>
          </div>
        </div>
      </div>

      <!-- 4. Tap-Dance -->
      <div class="kanata-card" data-viz="tap-dance">
        <div class="card-text">
          <h3>Tap-Dance</h3>
          <p>Different actions based on tap count</p>
        </div>
        <div class="kanata-viz">
          <div class="track">
            <span class="count-badge badge-1">×1</span>
            <span class="count-badge badge-2">×2</span>
            <span class="count-badge badge-3">×3</span>
            <div class="block block--blue tap-1">Q</div>
            <div class="block block--blue tap-2">Q</div>
            <div class="block block--blue tap-3">Q</div>
            <div class="block block--green result-block">Quit App</div>
          </div>
        </div>
      </div>

      <!-- 5. Leader Keys -->
      <div class="kanata-card" data-viz="leader">
        <div class="card-text">
          <h3>Leader Keys</h3>
          <p>Press leader, then a sequence</p>
        </div>
        <div class="kanata-viz">
          <div class="track">
            <div class="block block--orange leader-block">SPC</div>
            <span class="arrow arrow-1">→</span>
            <div class="block block--blue seq-1">G</div>
            <div class="block block--blue seq-2">S</div>
            <div class="block block--green result-out">Git Status</div>
          </div>
        </div>
      </div>

      <!-- 6. Sequences -->
      <div class="kanata-card" data-viz="sequence">
        <div class="card-text">
          <h3>Sequences</h3>
          <p>Keys in order trigger an action</p>
        </div>
        <div class="kanata-viz">
          <div class="track">
            <div class="block block--blue seq-a">D</div>
            <div class="block block--blue seq-b">D</div>
            <div class="block block--blue seq-c">S</div>
            <div class="block block--green seq-result">Save All</div>
            <div class="timing-bracket"><span>&lt;500ms</span></div>
          </div>
        </div>
      </div>

      <!-- 7. One-Shot Modifiers -->
      <div class="kanata-card" data-viz="oneshot">
        <div class="card-text">
          <h3>One-Shot</h3>
          <p>Modifier applies to next key only</p>
        </div>
        <div class="kanata-viz">
          <div class="track">
            <div class="block block--orange osm-block">⇧ 1×</div>
            <span class="arrow osm-arrow">→</span>
            <div class="block block--blue osm-target">a</div>
            <span class="osm-result">A</span>
          </div>
        </div>
      </div>

      <!-- 8. Sticky Keys -->
      <div class="kanata-card" data-viz="sticky">
        <div class="card-text">
          <h3>Sticky Keys</h3>
          <p>Toggle modifiers on/off</p>
        </div>
        <div class="kanata-viz">
          <div class="track">
            <div class="block block--orange sticky-mod">⇧</div>
            <div class="block block--blue sticky-a">A</div>
            <div class="block block--blue sticky-b">B</div>
            <div class="block block--blue sticky-c">C</div>
            <span class="sticky-result">→ ABC</span>
          </div>
        </div>
      </div>

      <!-- 9. Macros -->
      <div class="kanata-card" data-viz="macro">
        <div class="card-text">
          <h3>Macros</h3>
          <p>Multiple keystrokes from one trigger</p>
        </div>
        <div class="kanata-viz">
          <div class="track">
            <div class="block block--purple macro-trigger">SAVE</div>
            <span class="macro-arrow">→</span>
            <div class="block block--blue macro-out-1">⌘</div>
            <div class="block block--blue macro-out-2">S</div>
            <div class="block block--blue macro-out-3">⌘</div>
            <div class="block block--blue macro-out-4">W</div>
          </div>
        </div>
      </div>

      <!-- 10. Caps-Word -->
      <div class="kanata-card" data-viz="capsword">
        <div class="card-text">
          <h3>Caps-Word</h3>
          <p>Auto-caps until space or punctuation</p>
        </div>
        <div class="kanata-viz">
          <div class="track">
            <div class="block block--orange cw-trigger">CAPS</div>
            <div class="block block--green cw-h">H</div>
            <div class="block block--green cw-e">E</div>
            <div class="block block--green cw-l">L</div>
            <div class="block block--green cw-l2">L</div>
            <div class="block block--green cw-o">O</div>
            <div class="block block--white cw-space">␣</div>
          </div>
        </div>
      </div>

      <!-- 11. Fork/Switch -->
      <div class="kanata-card" data-viz="fork">
        <div class="card-text">
          <h3>Fork / Switch</h3>
          <p>Conditional actions based on other keys</p>
        </div>
        <div class="kanata-viz">
          <div class="multi-track">
            <div class="track-row">
              <span class="track-label">+ Shift</span>
              <div class="track">
                <div class="block block--blue fork-input">X</div>
                <div class="block block--purple fork-check">Shift?</div>
                <div class="block block--green fork-yes">CUT</div>
              </div>
            </div>
            <div class="track-row">
              <span class="track-label">No Shift</span>
              <div class="track">
                <div class="block block--blue fork-input">X</div>
                <div class="block block--purple fork-check">Shift?</div>
                <div class="block block--white fork-no">x</div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>

  <!-- Piano Roll Visualization -->
  <div class="viz-panel" id="viz-piano-roll" role="tabpanel">
    <div class="piano-roll-grid">
      <!-- 1. Chords -->
      <div class="pr-card" data-pr="chord">
        <div class="pr-card-text">
          <h3>Chords</h3>
          <p>Press multiple keys simultaneously for a new action</p>
        </div>
        <div class="pr-keys">
          <div class="pr-key pr-key--white">J</div>
          <div class="pr-key pr-key--white">K</div>
          <div class="pr-key pr-key--white">L</div>
        </div>
        <div class="pr-grid">
          <div class="pr-playhead"></div>
          <div class="pr-note pr-note--chord pr-note-1">J</div>
          <div class="pr-note pr-note--chord pr-note-2">K</div>
          <div class="pr-note pr-note--chord pr-note-3">L</div>
          <div class="pr-note pr-note--chord pr-note-out">Esc</div>
        </div>
      </div>

      <!-- 2. Layers -->
      <div class="pr-card" data-pr="layer">
        <div class="pr-card-text">
          <h3>Layers</h3>
          <p>Switch entire key layouts on the fly</p>
        </div>
        <div class="pr-keys">
          <div class="pr-key pr-key--white">Base</div>
          <div class="pr-key pr-key--black">Fn</div>
          <div class="pr-key pr-key--white">Nav</div>
          <div class="pr-key pr-key--black">Sym</div>
        </div>
        <div class="pr-grid">
          <div class="pr-playhead"></div>
          <div class="pr-note pr-note--layer pr-note-base">qwerty</div>
          <div class="pr-note pr-note--layer pr-note-fn">F1-F12</div>
          <div class="pr-note pr-note--layer pr-note-nav">arrows</div>
          <div class="pr-note pr-note--layer pr-note-sym">!@#$</div>
        </div>
      </div>

      <!-- 3. Tap-Hold -->
      <div class="pr-card" data-pr="tap-hold">
        <div class="pr-card-text">
          <h3>Tap-Hold</h3>
          <p>Tap for one action, hold for another</p>
        </div>
        <div class="pr-keys">
          <div class="pr-key pr-key--white">Tap</div>
          <div class="pr-key pr-key--black"></div>
          <div class="pr-key pr-key--white">Hold</div>
        </div>
        <div class="pr-grid">
          <div class="pr-playhead"></div>
          <div class="pr-note pr-note--tap pr-note-tap">A</div>
          <div class="pr-note pr-note--tap pr-note-tap-out">a</div>
          <div class="pr-note pr-note--hold pr-note-hold">A</div>
          <div class="pr-note pr-note--hold pr-note-hold-out">Ctrl</div>
        </div>
      </div>

      <!-- 4. Tap-Dance -->
      <div class="pr-card" data-pr="tap-dance">
        <div class="pr-card-text">
          <h3>Tap-Dance</h3>
          <p>Different actions for single, double, triple tap</p>
        </div>
        <div class="pr-keys">
          <div class="pr-key pr-key--white">1x</div>
          <div class="pr-key pr-key--white">2x</div>
          <div class="pr-key pr-key--white">3x</div>
        </div>
        <div class="pr-grid">
          <div class="pr-playhead"></div>
          <div class="pr-note pr-note--tap pr-note-t1">Q</div>
          <div class="pr-note pr-note--tap pr-note-t2">Q</div>
          <div class="pr-note pr-note--tap pr-note-t3">Q</div>
          <div class="pr-note pr-note--tap pr-note-out1">q</div>
          <div class="pr-note pr-note--tap pr-note-out2">Esc</div>
          <div class="pr-note pr-note--tap pr-note-out3">Caps</div>
        </div>
      </div>

      <!-- 5. Leader Keys -->
      <div class="pr-card" data-pr="leader">
        <div class="pr-card-text">
          <h3>Leader Keys</h3>
          <p>Start a command sequence with a prefix key</p>
        </div>
        <div class="pr-keys">
          <div class="pr-key pr-key--white"></div>
          <div class="pr-key pr-key--white">Seq</div>
          <div class="pr-key pr-key--white"></div>
        </div>
        <div class="pr-grid">
          <div class="pr-playhead"></div>
          <div class="pr-note pr-note--leader pr-note-ldr">LDR</div>
          <div class="pr-note pr-note--leader pr-note-seq1">G</div>
          <div class="pr-note pr-note--leader pr-note-seq2">S</div>
          <div class="pr-note pr-note--leader pr-note-action">Slack</div>
        </div>
      </div>

      <!-- 6. Sequences -->
      <div class="pr-card" data-pr="seq">
        <div class="pr-card-text">
          <h3>Sequences</h3>
          <p>Type abbreviations that expand to full text</p>
        </div>
        <div class="pr-keys">
          <div class="pr-key pr-key--white"></div>
          <div class="pr-key pr-key--white">Abbr</div>
          <div class="pr-key pr-key--white"></div>
        </div>
        <div class="pr-grid">
          <div class="pr-playhead"></div>
          <div class="pr-note pr-note--seq pr-note-s1">a</div>
          <div class="pr-note pr-note--seq pr-note-s2">d</div>
          <div class="pr-note pr-note--seq pr-note-s3">d</div>
          <div class="pr-note pr-note--seq pr-note-s4">r</div>
          <div class="pr-note pr-note--seq pr-note-expand">address</div>
        </div>
      </div>

      <!-- 7. One-Shot Modifiers -->
      <div class="pr-card" data-pr="osm">
        <div class="pr-card-text">
          <h3>One-Shot Modifiers</h3>
          <p>Tap modifier, then tap key (no holding)</p>
        </div>
        <div class="pr-keys">
          <div class="pr-key pr-key--white">Mod</div>
          <div class="pr-key pr-key--black"></div>
          <div class="pr-key pr-key--white">Key</div>
        </div>
        <div class="pr-grid">
          <div class="pr-playhead"></div>
          <div class="pr-note pr-note--osm pr-note-mod">Shift</div>
          <div class="pr-note pr-note--osm pr-note-key">A</div>
          <div class="pr-note pr-note--osm pr-note-combined">A</div>
        </div>
      </div>

      <!-- 8. Sticky Keys -->
      <div class="pr-card" data-pr="sticky">
        <div class="pr-card-text">
          <h3>Sticky Keys</h3>
          <p>Modifier stays active until you tap it again</p>
        </div>
        <div class="pr-keys">
          <div class="pr-key pr-key--white">Lock</div>
          <div class="pr-key pr-key--white">Held</div>
          <div class="pr-key pr-key--white">Keys</div>
        </div>
        <div class="pr-grid">
          <div class="pr-playhead"></div>
          <div class="pr-note pr-note--sticky pr-note-stick">Ctrl</div>
          <div class="pr-note pr-note--sticky pr-note-held"></div>
          <div class="pr-note pr-note--sticky pr-note-k1">A</div>
          <div class="pr-note pr-note--sticky pr-note-k2">C</div>
          <div class="pr-note pr-note--sticky pr-note-k3">V</div>
        </div>
      </div>

      <!-- 9. Macros -->
      <div class="pr-card" data-pr="macro">
        <div class="pr-card-text">
          <h3>Macros</h3>
          <p>One key triggers a sequence of keystrokes</p>
        </div>
        <div class="pr-keys">
          <div class="pr-key pr-key--white">1</div>
          <div class="pr-key pr-key--white">2</div>
          <div class="pr-key pr-key--white">3</div>
          <div class="pr-key pr-key--white">4</div>
        </div>
        <div class="pr-grid">
          <div class="pr-playhead"></div>
          <div class="pr-note pr-note--macro pr-note-trigger">SAVE</div>
          <div class="pr-note pr-note--macro pr-note-m1">⌘</div>
          <div class="pr-note pr-note--macro pr-note-m2">S</div>
          <div class="pr-note pr-note--macro pr-note-m3">⌘</div>
          <div class="pr-note pr-note--macro pr-note-m4">W</div>
        </div>
      </div>

      <!-- 10. Caps-Word -->
      <div class="pr-card" data-pr="caps">
        <div class="pr-card-text">
          <h3>Caps-Word</h3>
          <p>Auto-caps until you hit space or punctuation</p>
        </div>
        <div class="pr-keys">
          <div class="pr-key pr-key--white">Caps</div>
          <div class="pr-key pr-key--white">Type</div>
          <div class="pr-key pr-key--white">End</div>
        </div>
        <div class="pr-grid">
          <div class="pr-playhead"></div>
          <div class="pr-note pr-note--caps pr-note-activate">CW</div>
          <div class="pr-note pr-note--caps pr-note-c1">H</div>
          <div class="pr-note pr-note--caps pr-note-c2">E</div>
          <div class="pr-note pr-note--caps pr-note-c3">L</div>
          <div class="pr-note pr-note--caps pr-note-c4">L</div>
          <div class="pr-note pr-note--caps pr-note-c5">O</div>
          <div class="pr-note pr-note--caps pr-note-space">␣</div>
        </div>
      </div>

      <!-- 11. Fork/Switch -->
      <div class="pr-card" data-pr="fork">
        <div class="pr-card-text">
          <h3>Fork / Switch</h3>
          <p>Choose action based on what other keys are held</p>
        </div>
        <div class="pr-keys">
          <div class="pr-key pr-key--white">+Shift</div>
          <div class="pr-key pr-key--black"></div>
          <div class="pr-key pr-key--white">No Shift</div>
        </div>
        <div class="pr-grid">
          <div class="pr-playhead"></div>
          <div class="pr-note pr-note--fork pr-note-input">X</div>
          <div class="pr-note pr-note--fork pr-note-check">Shift?</div>
          <span class="fork-arrow-up">↗</span>
          <span class="fork-arrow-down">↘</span>
          <div class="pr-note pr-note--fork pr-note-yes">CUT</div>
          <div class="pr-note pr-note--fork pr-note-no">x</div>
        </div>
      </div>
    </div>
  </div>
  </section>

  <!-- DESIGN #6: MINIMAL GEOMETRIC -->
  <section class="geometric-section">
    <h2>What KeyPath Can Do</h2>
    <p class="section-subtitle">Keyboard remapping, window management, app launching, and more.</p>

    <div class="geometric-grid">
      <!-- Basic Remapping -->
      <div class="geo-card" data-feature="remap" data-geo>
        <svg viewBox="0 0 280 160">
          <rect class="geo-key" x="40" y="60" width="50" height="50" rx="8"/>
          <text class="geo-key-label" x="65" y="85">A</text>
          <path class="geo-arrow" d="M100 85 L140 85 L135 80 M140 85 L135 90"/>
          <circle class="geo-halo" cx="205" cy="85" r="35"/>
          <rect class="geo-key active" x="180" y="60" width="50" height="50" rx="8"/>
          <text class="geo-key-label" x="205" y="85" fill="#FFF">B</text>
        </svg>
        <h3>Basic Remapping</h3>
        <p>Transform any key into any other. Swap Caps Lock to Escape, or remap your entire layout.</p>
      </div>

      <!-- Tap-Hold -->
      <div class="geo-card" data-feature="tap-hold" data-geo>
        <svg viewBox="0 0 280 160">
          <circle class="geo-timer-ring" cx="140" cy="80" r="40" fill="none" stroke="#E8E8ED" stroke-width="4"/>
          <circle class="geo-progress" cx="140" cy="80" r="25"/>
          <rect class="geo-key" x="115" y="55" width="50" height="50" rx="8"/>
          <text class="geo-key-label" x="140" y="72">TAP</text>
          <text class="geo-key-label" x="140" y="92" font-size="11" fill="#86868B">HOLD</text>
        </svg>
        <h3>Tap-Hold</h3>
        <p>One key, two purposes. Tap for one action, hold for another. Maximum efficiency.</p>
      </div>

      <!-- Layers -->
      <div class="geo-card" data-feature="layers" data-geo>
        <svg viewBox="0 0 280 160">
          <g transform="translate(90, 30)">
            <rect class="geo-layer" x="0" y="80" width="100" height="40" rx="6"/>
            <rect class="geo-layer" x="10" y="50" width="100" height="40" rx="6"/>
            <rect class="geo-layer" x="20" y="20" width="100" height="40" rx="6"/>
          </g>
          <text class="geo-key-label" x="160" y="55" font-size="12" fill="#FFF">ACTIVE</text>
        </svg>
        <h3>Layers</h3>
        <p>Stack keyboard layouts like transparent sheets. Switch instantly between navigation, symbols, and more.</p>
      </div>

      <!-- Home Row Mods -->
      <div class="geo-card" data-feature="home-row-mods" data-geo>
        <svg viewBox="0 0 280 160">
          <!-- Home row keys -->
          <rect class="geo-key" x="30" y="55" width="45" height="50" rx="8"/>
          <text class="geo-key-label" x="52" y="72" font-size="14">A</text>
          <text class="geo-key-label" x="52" y="92" font-size="9" fill="#86868B">Ctrl</text>
          <rect class="geo-key" x="80" y="55" width="45" height="50" rx="8"/>
          <text class="geo-key-label" x="102" y="72" font-size="14">S</text>
          <text class="geo-key-label" x="102" y="92" font-size="9" fill="#86868B">Alt</text>
          <rect class="geo-key" x="130" y="55" width="45" height="50" rx="8"/>
          <text class="geo-key-label" x="152" y="72" font-size="14">D</text>
          <text class="geo-key-label" x="152" y="92" font-size="9" fill="#86868B">Cmd</text>
          <rect class="geo-key" x="180" y="55" width="45" height="50" rx="8"/>
          <text class="geo-key-label" x="202" y="72" font-size="14">F</text>
          <text class="geo-key-label" x="202" y="92" font-size="9" fill="#86868B">Shift</text>
          <!-- Indicator dots -->
          <circle cx="52" cy="115" r="4" fill="#0071E3" class="geo-hrm-dot"/>
          <circle cx="102" cy="115" r="4" fill="#FF9500" class="geo-hrm-dot"/>
          <circle cx="152" cy="115" r="4" fill="#AF52DE" class="geo-hrm-dot"/>
          <circle cx="202" cy="115" r="4" fill="#34C759" class="geo-hrm-dot"/>
        </svg>
        <h3>Home Row Mods</h3>
        <p>Modifiers on your home row. Tap for letters, hold for Ctrl, Alt, Cmd, Shift. No finger gymnastics.</p>
      </div>

      <!-- Vim Navigation -->
      <div class="geo-card" data-feature="vim-nav" data-geo>
        <svg viewBox="0 0 280 160">
          <!-- HJKL keys -->
          <rect class="geo-key" x="30" y="55" width="45" height="50" rx="8"/>
          <text class="geo-key-label" x="52" y="80">H</text>
          <rect class="geo-key" x="80" y="55" width="45" height="50" rx="8"/>
          <text class="geo-key-label" x="102" y="80">J</text>
          <rect class="geo-key" x="130" y="55" width="45" height="50" rx="8"/>
          <text class="geo-key-label" x="152" y="80">K</text>
          <rect class="geo-key" x="180" y="55" width="45" height="50" rx="8"/>
          <text class="geo-key-label" x="202" y="80">L</text>
          <!-- Arrow indicators below -->
          <text x="52" y="125" font-size="18" fill="#0071E3" text-anchor="middle">←</text>
          <text x="102" y="125" font-size="18" fill="#0071E3" text-anchor="middle">↓</text>
          <text x="152" y="125" font-size="18" fill="#0071E3" text-anchor="middle">↑</text>
          <text x="202" y="125" font-size="18" fill="#0071E3" text-anchor="middle">→</text>
        </svg>
        <h3>Vim Navigation</h3>
        <p>HJKL as arrow keys. Navigate text, code, and apps without leaving home row. Vim muscle memory everywhere.</p>
      </div>

      <!-- Macros -->
      <div class="geo-card" data-feature="macros" data-geo>
        <svg viewBox="0 0 280 160">
          <g class="geo-macro-step">
            <rect x="40" y="30" width="60" height="30" rx="6" fill="#F5F5F7" stroke="#D2D2D7" stroke-width="1.5"/>
            <text class="geo-key-label" x="70" y="45" font-size="11">⌘S</text>
          </g>
          <g class="geo-macro-step">
            <rect x="40" y="65" width="60" height="30" rx="6" fill="#F5F5F7" stroke="#D2D2D7" stroke-width="1.5"/>
            <text class="geo-key-label" x="70" y="80" font-size="11">⌘W</text>
          </g>
          <g class="geo-macro-step">
            <rect x="40" y="100" width="60" height="30" rx="6" fill="#F5F5F7" stroke="#D2D2D7" stroke-width="1.5"/>
            <text class="geo-key-label" x="70" y="115" font-size="11">⌘Q</text>
          </g>
          <path class="geo-arrow" d="M110 45 L130 45 M110 80 L130 80 M110 115 L130 115 M130 45 L130 115" stroke-dasharray="none"/>
          <rect class="geo-key active" x="150" y="55" width="90" height="50" rx="8"/>
          <text class="geo-key-label" x="195" y="80" fill="#FFF" font-size="12">MACRO</text>
        </svg>
        <h3>Macros</h3>
        <p>Chain multiple actions into one key. Save, close, and quit—all with a single press.</p>
      </div>

      <!-- Launch Apps -->
      <div class="geo-card" data-feature="launch-app" data-geo>
        <svg viewBox="0 0 280 160">
          <!-- Keyboard key -->
          <rect class="geo-key" x="30" y="55" width="50" height="50" rx="8"/>
          <text class="geo-key-label" x="55" y="80">O</text>
          <!-- Arrow -->
          <path class="geo-arrow" d="M90 80 L130 80 L125 75 M130 80 L125 85"/>
          <!-- App grid -->
          <g class="geo-app-icon" transform="translate(150, 55)">
            <rect x="0" y="0" width="22" height="22" rx="5" fill="#007AFF"/>
            <rect x="26" y="0" width="22" height="22" rx="5" fill="#34C759"/>
            <rect x="52" y="0" width="22" height="22" rx="5" fill="#FF9500"/>
            <rect x="0" y="26" width="22" height="22" rx="5" fill="#AF52DE"/>
            <rect x="26" y="26" width="22" height="22" rx="5" fill="#FF3B30"/>
            <rect x="52" y="26" width="22" height="22" rx="5" fill="#5856D6"/>
          </g>
        </svg>
        <h3>Launch Apps</h3>
        <p>Open any app with a keystroke. No dock, no Spotlight. Instant access to your tools.</p>
      </div>

      <!-- Window Arranging -->
      <div class="geo-card" data-feature="window-snap" data-geo>
        <svg viewBox="0 0 280 160">
          <!-- Monitor outline -->
          <rect x="40" y="25" width="200" height="110" rx="8" fill="none" stroke="#D2D2D7" stroke-width="2"/>
          <!-- Window positions -->
          <rect class="geo-window geo-window-left" x="45" y="30" width="95" height="100" rx="4" fill="#0071E3" opacity="0.15"/>
          <rect class="geo-window geo-window-right" x="145" y="30" width="90" height="100" rx="4" fill="#0071E3" opacity="0"/>
          <!-- Arrows showing movement -->
          <g class="geo-snap-arrows">
            <path d="M140 80 L100 80" stroke="#0071E3" stroke-width="2" stroke-linecap="round" fill="none" opacity="0.6"/>
            <path d="M100 80 L108 74 M100 80 L108 86" stroke="#0071E3" stroke-width="2" stroke-linecap="round" fill="none" opacity="0.6"/>
          </g>
          <!-- Key hints -->
          <text class="geo-key-label" x="92" y="85" font-size="16" fill="#0071E3">H</text>
          <text class="geo-key-label" x="188" y="85" font-size="16" fill="#86868B">L</text>
        </svg>
        <h3>Window Arranging</h3>
        <p>Snap windows to halves, quarters, or maximize. Tile your workspace without touching the mouse.</p>
      </div>
    </div>
  </section>

  <div class="kanata-landing-divider" aria-hidden="true"></div>

  <section class="kanata-landing-section">
    <h2 class="mt-0">Ready?</h2>
    <p>Download KeyPath and start customizing your keyboard.</p>
    <div class="kanata-landing-actions">
      <a class="button button-orange" href="https://github.com/malpern/KeyPath/releases/download/v1.0.0/KeyPath-1.0.0.zip">Download <span class="button-badge">Free</span></a>
      <a class="button button-secondary" href="{{ site.github_url }}/discussions">Ask a question</a>
    </div>
  </section>

</div>

<!-- rebuild trigger -->
