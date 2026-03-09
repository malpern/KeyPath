---
layout: default
title: Split Runtime Cutover
description: An interactive explanation of why KeyPath moved from a single Kanata runtime path to a split runtime architecture on macOS.
max_width: 1160px
content_class: architecture-cutover-page
---

<style>
  .architecture-cutover-page {
    --story-bg: linear-gradient(180deg, rgba(7, 64, 130, 0.05), rgba(255, 255, 255, 0));
    --panel-bg: rgba(255, 255, 255, 0.82);
    --panel-border: rgba(15, 23, 42, 0.08);
    --panel-shadow: 0 24px 60px rgba(15, 23, 42, 0.08);
    --ink-strong: #111827;
    --ink-muted: #4b5563;
    --blue: #0a84ff;
    --cyan: #64d2ff;
    --green: #30d158;
    --amber: #f59e0b;
    --red: #ff453a;
    --violet: #5e5ce6;
    --grid-gap: 1.25rem;
  }

  @media (prefers-color-scheme: dark) {
    .architecture-cutover-page {
      --story-bg: linear-gradient(180deg, rgba(10, 132, 255, 0.16), rgba(0, 0, 0, 0));
      --panel-bg: rgba(28, 28, 30, 0.9);
      --panel-border: rgba(255, 255, 255, 0.08);
      --panel-shadow: 0 24px 60px rgba(0, 0, 0, 0.28);
      --ink-strong: #f5f5f7;
      --ink-muted: #c7c7cc;
      --amber: #f5b642;
    }
  }

  .cutover-hero {
    position: relative;
    overflow: hidden;
    padding: 2.75rem;
    border: 1px solid var(--panel-border);
    border-radius: 32px;
    background:
      radial-gradient(circle at top right, rgba(100, 210, 255, 0.28), transparent 32%),
      radial-gradient(circle at bottom left, rgba(48, 209, 88, 0.16), transparent 34%),
      var(--story-bg);
    box-shadow: var(--panel-shadow);
  }

  .cutover-eyebrow,
  .cutover-kicker {
    display: inline-flex;
    align-items: center;
    gap: 0.45rem;
    padding: 0.35rem 0.7rem;
    border-radius: 999px;
    border: 1px solid rgba(10, 132, 255, 0.18);
    background: rgba(10, 132, 255, 0.09);
    color: var(--blue);
    font-size: 0.82rem;
    font-weight: 700;
    letter-spacing: 0.02em;
    text-transform: uppercase;
    margin-bottom: 1rem;
  }

  .cutover-hero h1 {
    font-size: clamp(2.8rem, 5vw, 4.6rem);
    line-height: 0.98;
    letter-spacing: -0.045em;
    max-width: 10ch;
    margin-bottom: 1rem;
  }

  .cutover-lede {
    max-width: 64ch;
    font-size: 1.18rem;
    line-height: 1.65;
    color: var(--ink-muted);
  }

  .cutover-hero-grid,
  .cutover-problem-grid,
  .cutover-advantage-grid,
  .cutover-principles,
  .cutover-summary-grid {
    display: grid;
    gap: var(--grid-gap);
  }

  .cutover-hero-grid {
    grid-template-columns: minmax(0, 1.5fr) minmax(320px, 1fr);
    align-items: end;
    gap: 2rem;
  }

  .cutover-stat-card,
  .cutover-problem-card,
  .cutover-principle-card,
  .cutover-summary-card {
    background: var(--panel-bg);
    border: 1px solid var(--panel-border);
    border-radius: 24px;
    box-shadow: var(--panel-shadow);
  }

  .cutover-stat-card {
    padding: 1.15rem 1.2rem;
  }

  .cutover-stat-card strong {
    display: block;
    font-size: 1.85rem;
    line-height: 1;
    color: var(--ink-strong);
    margin-bottom: 0.35rem;
  }

  .cutover-stat-card span,
  .cutover-problem-card p,
  .cutover-principle-card p,
  .cutover-summary-card p,
  .cutover-advantage-card p {
    color: var(--ink-muted);
  }

  .cutover-hero-aside {
    display: grid;
    gap: 1rem;
  }

  .cutover-note {
    padding: 1.15rem 1.2rem;
  }

  .cutover-note h3,
  .cutover-problem-card h3,
  .cutover-principle-card h3,
  .cutover-summary-card h3,
  .cutover-advantage-card h3 {
    font-size: 1.05rem;
    margin: 0 0 0.45rem;
  }

  .cutover-section {
    margin-top: 2.25rem;
  }

  .cutover-section h2 {
    margin-top: 0;
    margin-bottom: 0.75rem;
  }

  .cutover-problem-grid,
  .cutover-advantage-grid,
  .cutover-principles,
  .cutover-summary-grid {
    grid-template-columns: repeat(3, minmax(0, 1fr));
  }

  .cutover-problem-card,
  .cutover-advantage-card,
  .cutover-principle-card,
  .cutover-summary-card {
    padding: 1.35rem;
  }

  .cutover-problem-card {
    border-top: 4px solid var(--red);
  }

  .cutover-advantage-card {
    background: var(--panel-bg);
    border: 1px solid var(--panel-border);
    border-radius: 24px;
    border-top: 4px solid var(--green);
    box-shadow: var(--panel-shadow);
  }

  .cutover-principle-card {
    border-top: 4px solid var(--blue);
  }

  .cutover-summary-card {
    border-top: 4px solid var(--violet);
  }

  .cutover-viewer {
    margin-top: 2.6rem;
    padding: 1.2rem;
    border-radius: 32px;
    border: 1px solid var(--panel-border);
    background:
      linear-gradient(180deg, rgba(255, 255, 255, 0.34), rgba(255, 255, 255, 0.12)),
      rgba(245, 245, 247, 0.72);
    box-shadow: var(--panel-shadow);
  }

  @media (prefers-color-scheme: dark) {
    .cutover-viewer {
      background:
        linear-gradient(180deg, rgba(255, 255, 255, 0.04), rgba(255, 255, 255, 0.01)),
        rgba(18, 18, 20, 0.92);
    }
  }

  .cutover-viewer-topbar {
    display: flex;
    flex-wrap: wrap;
    justify-content: space-between;
    gap: 1rem;
    align-items: center;
    margin-bottom: 1rem;
  }

  .cutover-segmented,
  .cutover-steps {
    display: inline-flex;
    flex-wrap: wrap;
    gap: 0.55rem;
    padding: 0.35rem;
    border-radius: 999px;
    background: rgba(127, 127, 127, 0.08);
    border: 1px solid var(--panel-border);
  }

  .cutover-segmented button,
  .cutover-steps button,
  .cutover-replay {
    appearance: none;
    border: 0;
    cursor: pointer;
    border-radius: 999px;
    padding: 0.7rem 1rem;
    font: inherit;
    color: var(--ink-muted);
    background: transparent;
    transition: transform 140ms ease, background-color 140ms ease, color 140ms ease, box-shadow 140ms ease;
  }

  .cutover-segmented button.is-active,
  .cutover-steps button.is-active,
  .cutover-replay:hover,
  .cutover-replay:focus-visible {
    color: #fff;
    background: linear-gradient(135deg, var(--blue), var(--cyan));
    box-shadow: 0 10px 24px rgba(10, 132, 255, 0.24);
  }

  .cutover-segmented button:hover,
  .cutover-steps button:hover {
    transform: translateY(-1px);
  }

  .cutover-replay {
    border: 1px solid var(--panel-border);
    background: var(--panel-bg);
    color: var(--ink-strong);
  }

  .cutover-visual-grid {
    display: grid;
    grid-template-columns: minmax(0, 1.65fr) minmax(290px, 0.9fr);
    gap: 1rem;
  }

  .cutover-diagram,
  .cutover-explainer {
    min-height: 720px;
    padding: 1.2rem;
    border-radius: 26px;
    background: var(--panel-bg);
    border: 1px solid var(--panel-border);
  }

  .cutover-diagram {
    position: relative;
    overflow: hidden;
  }

  .cutover-diagram-grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 1rem;
    height: 100%;
  }

  .cutover-column {
    position: relative;
    padding: 1rem;
    border-radius: 22px;
    border: 1px solid var(--panel-border);
    background:
      linear-gradient(180deg, rgba(10, 132, 255, 0.06), rgba(10, 132, 255, 0)),
      rgba(127, 127, 127, 0.02);
  }

  .cutover-column h3 {
    margin: 0 0 0.35rem;
  }

  .cutover-column p {
    margin-bottom: 1rem;
  }

  .cutover-node-stack {
    display: grid;
    gap: 0.8rem;
  }

  .cutover-node {
    position: relative;
    padding: 0.95rem;
    border-radius: 20px;
    border: 1px solid var(--panel-border);
    background: rgba(255, 255, 255, 0.72);
    transition: transform 180ms ease, border-color 180ms ease, box-shadow 180ms ease, opacity 180ms ease;
  }

  @media (prefers-color-scheme: dark) {
    .cutover-node {
      background: rgba(28, 28, 30, 0.92);
    }
  }

  .cutover-node small {
    display: block;
    color: var(--blue);
    font-size: 0.75rem;
    letter-spacing: 0.04em;
    text-transform: uppercase;
    margin-bottom: 0.35rem;
  }

  .cutover-node strong {
    display: block;
    color: var(--ink-strong);
    font-size: 1rem;
    margin-bottom: 0.18rem;
  }

  .cutover-node p {
    margin: 0;
    font-size: 0.95rem;
    line-height: 1.55;
  }

  .cutover-node.is-dimmed {
    opacity: 0.42;
  }

  .cutover-node.is-highlighted {
    transform: translateY(-2px);
    border-color: rgba(10, 132, 255, 0.42);
    box-shadow: 0 18px 36px rgba(10, 132, 255, 0.14);
  }

  .cutover-node.problem {
    border-left: 4px solid var(--red);
  }

  .cutover-node.good {
    border-left: 4px solid var(--green);
  }

  .cutover-node.neutral {
    border-left: 4px solid var(--blue);
  }

  .cutover-link {
    position: relative;
    display: flex;
    align-items: center;
    gap: 0.65rem;
    padding: 0.25rem 0.3rem;
    margin: 0.1rem 0;
    color: var(--ink-muted);
    font-size: 0.92rem;
    min-height: 36px;
  }

  .cutover-link::before {
    content: "";
    flex: 0 0 22px;
    height: 1px;
    background: linear-gradient(90deg, rgba(10, 132, 255, 0.18), rgba(10, 132, 255, 0.65));
  }

  .cutover-link::after {
    content: "";
    width: 8px;
    height: 8px;
    border-top: 2px solid rgba(10, 132, 255, 0.7);
    border-right: 2px solid rgba(10, 132, 255, 0.7);
    transform: rotate(45deg);
    margin-left: auto;
  }

  .cutover-link.is-dimmed {
    opacity: 0.28;
  }

  .cutover-link.is-active {
    color: var(--ink-strong);
    font-weight: 600;
  }

  .cutover-link.is-active::before {
    background: linear-gradient(90deg, var(--cyan), var(--blue));
    box-shadow: 0 0 14px rgba(10, 132, 255, 0.28);
  }

  .cutover-link.is-active::after {
    border-color: var(--blue);
  }

  .cutover-explainer {
    display: flex;
    flex-direction: column;
    gap: 1rem;
  }

  .cutover-phase {
    padding: 1rem;
    border-radius: 20px;
    border: 1px solid var(--panel-border);
    background: rgba(127, 127, 127, 0.04);
  }

  .cutover-phase-label {
    display: inline-flex;
    padding: 0.32rem 0.65rem;
    border-radius: 999px;
    background: rgba(10, 132, 255, 0.08);
    color: var(--blue);
    font-size: 0.76rem;
    font-weight: 700;
    letter-spacing: 0.03em;
    text-transform: uppercase;
    margin-bottom: 0.65rem;
  }

  .cutover-phase h3 {
    margin: 0 0 0.45rem;
    font-size: 1.28rem;
  }

  .cutover-phase p {
    margin-bottom: 0;
  }

  .cutover-phase-outcome {
    margin-top: auto;
    padding: 1rem;
    border-radius: 20px;
    border: 1px solid rgba(48, 209, 88, 0.22);
    background: linear-gradient(180deg, rgba(48, 209, 88, 0.1), rgba(48, 209, 88, 0.03));
  }

  .cutover-phase-outcome strong {
    display: block;
    margin-bottom: 0.4rem;
    color: var(--ink-strong);
  }

  .cutover-step-notes {
    list-style: none;
    padding: 0;
    margin: 0;
    display: grid;
    gap: 0.7rem;
  }

  .cutover-step-notes li {
    position: relative;
    padding-left: 1.1rem;
    color: var(--ink-muted);
  }

  .cutover-step-notes li::before {
    content: "";
    position: absolute;
    left: 0;
    top: 0.6rem;
    width: 0.42rem;
    height: 0.42rem;
    border-radius: 999px;
    background: linear-gradient(135deg, var(--blue), var(--cyan));
  }

  .cutover-legend {
    display: flex;
    flex-wrap: wrap;
    gap: 0.8rem;
    margin-top: 1rem;
  }

  .cutover-legend span {
    display: inline-flex;
    align-items: center;
    gap: 0.5rem;
    color: var(--ink-muted);
    font-size: 0.9rem;
  }

  .cutover-legend i {
    display: inline-block;
    width: 12px;
    height: 12px;
    border-radius: 999px;
  }

  .cutover-caption {
    margin-top: 1rem;
    padding: 1rem 1.1rem;
    border-radius: 18px;
    background: rgba(10, 132, 255, 0.06);
    color: var(--ink-muted);
  }

  .cutover-caption strong {
    color: var(--ink-strong);
  }

  .cutover-footnotes {
    margin-top: 2.25rem;
    padding: 1.2rem 1.4rem;
    border-radius: 24px;
    border: 1px solid var(--panel-border);
    background: var(--panel-bg);
  }

  .cutover-footnotes ul {
    margin: 0.8rem 0 0;
    padding-left: 1.15rem;
  }

  .cutover-footnotes li {
    color: var(--ink-muted);
    margin-bottom: 0.5rem;
  }

  @media (max-width: 980px) {
    .cutover-hero-grid,
    .cutover-visual-grid,
    .cutover-problem-grid,
    .cutover-advantage-grid,
    .cutover-principles,
    .cutover-summary-grid,
    .cutover-diagram-grid {
      grid-template-columns: 1fr;
    }

    .cutover-diagram,
    .cutover-explainer {
      min-height: auto;
    }
  }

  @media (max-width: 720px) {
    .cutover-hero,
    .cutover-viewer,
    .cutover-diagram,
    .cutover-explainer {
      padding: 1rem;
      border-radius: 24px;
    }

    .cutover-hero h1 {
      font-size: 2.5rem;
    }

    .cutover-segmented,
    .cutover-steps {
      width: 100%;
      justify-content: stretch;
    }

    .cutover-segmented button,
    .cutover-steps button {
      flex: 1 1 140px;
    }
  }
</style>

<div class="cutover-eyebrow">Architecture story</div>

<section class="cutover-hero">
  <div class="cutover-hero-grid">
    <div>
      <div class="cutover-kicker">PR #225 · Finalize split runtime cutover</div>
      <h1>One key press, two trust boundaries, one clear architecture.</h1>
      <p class="cutover-lede">
        KeyPath used to rely on a runtime path where the thing macOS launched, the thing users were told to trust,
        and the thing that actually touched the keyboard could drift apart. The split-runtime cutover fixes that by
        making the user-session host own input capture while a separate privileged bridge owns VirtualHID output.
      </p>
    </div>

    <div class="cutover-hero-aside">
      <div class="cutover-stat-card">
        <strong>Old mental model</strong>
        <span>“Kanata is the daemon.” That was simple to say, but wrong in important macOS-specific ways.</span>
      </div>
      <div class="cutover-stat-card">
        <strong>New mental model</strong>
        <span>“The app coordinates, the host captures input, the bridge emits output.” Each boundary now matches a real operating-system boundary.</span>
      </div>
      <div class="cutover-stat-card cutover-note">
        <h3>Why this matters on macOS</h3>
        <p>
          Input Monitoring is user-session oriented, while pqrs VirtualHID access still crosses a privileged boundary.
          Treating those as one process made health, permissions, and recovery harder to reason about.
        </p>
      </div>
    </div>
  </div>
</section>

<section class="cutover-section">
  <h2>Why the old approach had to change</h2>
  <p>
    The previous runtime worked often enough to look healthy, but it had three structural problems. They were not
    just bugs. They were signs that the architecture no longer matched how macOS actually grants permission and
    isolates privileged I/O.
  </p>

  <div class="cutover-problem-grid">
    <article class="cutover-problem-card">
      <h3>Permission identity drift</h3>
      <p>
        The launch subject, the canonical permission target, and the effective HID-owning process could disagree.
        That makes onboarding and debugging confusing for users and developers.
      </p>
    </article>
    <article class="cutover-problem-card">
      <h3>Registration was mistaken for liveness</h3>
      <p>
        `SMAppService` being enabled only means something is registered. It does not prove the runtime is actually
        running, responding, and capturing input.
      </p>
    </article>
    <article class="cutover-problem-card">
      <h3>Privileged output leaked into the input path</h3>
      <p>
        A user-session runtime could still trip over pqrs root-only boundaries because output readiness and event
        emission were too tightly coupled to the same runtime path.
      </p>
    </article>
  </div>
</section>

<section class="cutover-viewer" id="cutover-viewer">
  <div class="cutover-viewer-topbar">
    <div>
      <h2 style="margin-bottom:0.35rem;">Interactive architecture comparison</h2>
      <p style="margin-bottom:0;">Switch views, then step through a single key press to see where responsibility moves.</p>
    </div>

    <div class="cutover-segmented" role="tablist" aria-label="Architecture comparison view">
      <button type="button" class="is-active" data-cutover-view="legacy" aria-selected="true">Original architecture</button>
      <button type="button" data-cutover-view="split" aria-selected="false">New split runtime</button>
      <button type="button" data-cutover-view="diff" aria-selected="false">What changed</button>
    </div>
  </div>

  <div class="cutover-visual-grid">
    <div class="cutover-diagram">
      <div class="cutover-diagram-grid">
        <section class="cutover-column">
          <h3>Original architecture</h3>
          <p>A single runtime path carried too many responsibilities and too many assumptions.</p>

          <div class="cutover-node-stack">
            <div class="cutover-node neutral" data-node="legacy-app">
              <small>Orchestration</small>
              <strong>KeyPath.app</strong>
              <p>UI, configuration, diagnostics, and service control.</p>
            </div>
            <div class="cutover-link" data-link="legacy-1">Registers and starts a launcher/service</div>
            <div class="cutover-node neutral" data-node="legacy-launcher">
              <small>Launch identity</small>
              <strong>kanata-launcher</strong>
              <p>The thing launchd starts, but not necessarily the long-term runtime identity users reason about.</p>
            </div>
            <div class="cutover-link" data-link="legacy-2">Execs into the installed system binary</div>
            <div class="cutover-node problem" data-node="legacy-kanata">
              <small>Input + output + recovery</small>
              <strong>/Library/KeyPath/bin/kanata</strong>
              <p>Captures input, runs remapping logic, checks output readiness, and emits output through the same path.</p>
            </div>
            <div class="cutover-link" data-link="legacy-3">Touches root-sensitive output state directly</div>
            <div class="cutover-node problem" data-node="legacy-vhid">
              <small>Privileged boundary</small>
              <strong>pqrs VirtualHID / DriverKit</strong>
              <p>Required for output, but not aligned with the same trust model as Input Monitoring.</p>
            </div>
          </div>
        </section>

        <section class="cutover-column">
          <h3>New split runtime</h3>
          <p>Each component now owns one job and the trust boundaries are explicit.</p>

          <div class="cutover-node-stack">
            <div class="cutover-node neutral" data-node="split-app">
              <small>Orchestration</small>
              <strong>KeyPath.app</strong>
              <p>Still owns PermissionOracle, InstallerEngine, diagnostics, and high-level coordination.</p>
            </div>
            <div class="cutover-link" data-link="split-1">Prepares config, health checks, and bridge session</div>
            <div class="cutover-node good" data-node="split-host">
              <small>User-session input identity</small>
              <strong>Bundled runtime host</strong>
              <p>Owns HID capture and runs the Kanata runtime under the stable app-owned identity macOS sees.</p>
            </div>
            <div class="cutover-link" data-link="split-2">Forwards remapped output over a narrow protocol</div>
            <div class="cutover-node good" data-node="split-bridge">
              <small>Privileged output boundary</small>
              <strong>Output bridge companion</strong>
              <p>Owns the root-scoped path to VirtualHID and exposes handshake, emit, sync, reset, and health status.</p>
            </div>
            <div class="cutover-link" data-link="split-3">Delivers synthesized output without owning input permission</div>
            <div class="cutover-node good" data-node="split-vhid">
              <small>Privileged device access</small>
              <strong>pqrs VirtualHID / DriverKit</strong>
              <p>Still exists, but no longer drags the input-capture identity across the same boundary.</p>
            </div>
          </div>
        </section>
      </div>

      <div class="cutover-legend" aria-hidden="true">
        <span><i style="background: var(--blue);"></i> Stable ownership</span>
        <span><i style="background: var(--red);"></i> Legacy pain point</span>
        <span><i style="background: var(--green);"></i> New responsibility boundary</span>
      </div>

      <div class="cutover-caption" id="cutover-caption">
        <strong>Original architecture:</strong> the launcher, system binary, and user-facing permission story could diverge,
        which made failure analysis harder than it needed to be.
      </div>
    </div>

    <aside class="cutover-explainer">
      <div class="cutover-steps" role="tablist" aria-label="Key press flow steps">
        <button type="button" class="is-active" data-cutover-step="1" aria-selected="true">1. Start</button>
        <button type="button" data-cutover-step="2" aria-selected="false">2. Capture</button>
        <button type="button" data-cutover-step="3" aria-selected="false">3. Remap</button>
        <button type="button" data-cutover-step="4" aria-selected="false">4. Output</button>
        <button type="button" data-cutover-step="5" aria-selected="false">5. Recovery</button>
      </div>

      <section class="cutover-phase">
        <div class="cutover-phase-label" id="cutover-phase-label">Step 1</div>
        <h3 id="cutover-phase-title">How a key press enters the system</h3>
        <p id="cutover-phase-copy">
          In both architectures the app prepares configuration and launches the runtime path. The key question is:
          which process becomes the long-lived identity that macOS is really trusting?
        </p>
      </section>

      <section class="cutover-phase">
        <h3 style="font-size:1.02rem;">What to notice</h3>
        <ul class="cutover-step-notes" id="cutover-phase-notes">
          <li>The old path changes process identity before the runtime really settles.</li>
          <li>The new path keeps the input owner inside the app-owned host identity.</li>
          <li>That makes the permission story match the runtime story.</li>
        </ul>
      </section>

      <section class="cutover-phase-outcome">
        <strong id="cutover-outcome-title">Engineering payoff</strong>
        <div id="cutover-outcome-copy">
          Clear ownership is the foundation for good diagnostics. If the process graph is ambiguous, every higher-level
          health signal becomes harder to trust.
        </div>
      </section>

      <button type="button" class="cutover-replay" id="cutover-replay">Replay flow</button>
    </aside>
  </div>
</section>

<section class="cutover-section">
  <h2>What the new architecture improves</h2>
  <p>
    The split-runtime design is not just “more components.” It is a more accurate map of the operating system. That
    gives KeyPath better correctness, better upgrade behavior, and a cleaner story for novice contributors.
  </p>

  <div class="cutover-advantage-grid">
    <article class="cutover-advantage-card">
      <h3>Stable permission model</h3>
      <p>
        The process that opens HID devices is now the process whose identity matters. The permission contract is no
        longer hidden behind a launcher handoff.
      </p>
    </article>
    <article class="cutover-advantage-card">
      <h3>Better failure isolation</h3>
      <p>
        If input capture breaks, that is different from the output bridge breaking. Each problem has its own health
        surface, logs, and recovery path.
      </p>
    </article>
    <article class="cutover-advantage-card">
      <h3>Safer postcondition checks</h3>
      <p>
        Installer and repair flows can verify “running and actually ready” instead of assuming a registered daemon means
        everything is fine.
      </p>
    </article>
  </div>
</section>

<section class="cutover-section">
  <h2>Architecture rules this page is teaching</h2>
  <p>
    These are the deeper engineering ideas behind the cutover. They are the difference between a feature that “works on
    my machine” and a system that stays understandable after months of evolution.
  </p>

  <div class="cutover-principles">
    <article class="cutover-principle-card">
      <h3>Match code boundaries to OS boundaries</h3>
      <p>
        macOS does not treat input permission, launch registration, and privileged output as the same thing. The
        software should not pretend they are.
      </p>
    </article>
    <article class="cutover-principle-card">
      <h3>Keep ownership centralized</h3>
      <p>
        `PermissionOracle` still owns permission truth. `InstallerEngine` still owns installation and repair. The
        cutover refines runtime responsibilities without scattering decision-making.
      </p>
    </article>
    <article class="cutover-principle-card">
      <h3>Prefer narrow protocols at privilege boundaries</h3>
      <p>
        The output bridge only needs a versioned contract for handshake, emit, modifier sync, reset, and health. A
        small protocol is easier to secure, test, and evolve.
      </p>
    </article>
  </div>
</section>

<section class="cutover-section">
  <h2>What stays the same</h2>
  <div class="cutover-summary-grid">
    <article class="cutover-summary-card">
      <h3>Kanata still does remapping</h3>
      <p>The split runtime changes hosting and transport on macOS. It does not replace Kanata’s parsing or remapping core.</p>
    </article>
    <article class="cutover-summary-card">
      <h3>The app still coordinates</h3>
      <p>KeyPath.app remains the place where users see diagnostics, permissions guidance, and installation state.</p>
    </article>
    <article class="cutover-summary-card">
      <h3>Reliability is still verified, not assumed</h3>
      <p>The service lifecycle rules remain: registration metadata is not liveness, and success must be postcondition-verified.</p>
    </article>
  </div>
</section>

<section class="cutover-footnotes">
  <div class="cutover-kicker">Based on the implementation</div>
  <p>
    This page summarizes the split-runtime cutover described in PR #225 and the supporting design docs around the
    macOS runtime identity change, the bridge-host spike, and the Kanata backend seam.
  </p>
  <ul>
    <li>The core design target is a stable app-bundled input runtime identity paired with a separate privileged output path.</li>
    <li>The split was motivated by real runtime evidence, not by abstract layering preferences.</li>
    <li>The goal is boring reliability: clearer permissions, clearer diagnostics, and fewer hidden macOS-specific traps.</li>
  </ul>
</section>

<script>
  (() => {
    const viewer = document.getElementById('cutover-viewer');
    if (!viewer) return;

    const viewButtons = Array.from(viewer.querySelectorAll('[data-cutover-view]'));
    const stepButtons = Array.from(viewer.querySelectorAll('[data-cutover-step]'));
    const replayButton = document.getElementById('cutover-replay');
    const caption = document.getElementById('cutover-caption');
    const phaseLabel = document.getElementById('cutover-phase-label');
    const phaseTitle = document.getElementById('cutover-phase-title');
    const phaseCopy = document.getElementById('cutover-phase-copy');
    const phaseNotes = document.getElementById('cutover-phase-notes');
    const outcomeTitle = document.getElementById('cutover-outcome-title');
    const outcomeCopy = document.getElementById('cutover-outcome-copy');

    const nodes = {
      legacy: {
        app: viewer.querySelector('[data-node="legacy-app"]'),
        launcher: viewer.querySelector('[data-node="legacy-launcher"]'),
        kanata: viewer.querySelector('[data-node="legacy-kanata"]'),
        vhid: viewer.querySelector('[data-node="legacy-vhid"]')
      },
      split: {
        app: viewer.querySelector('[data-node="split-app"]'),
        host: viewer.querySelector('[data-node="split-host"]'),
        bridge: viewer.querySelector('[data-node="split-bridge"]'),
        vhid: viewer.querySelector('[data-node="split-vhid"]')
      }
    };

    const links = {
      legacy: [
        viewer.querySelector('[data-link="legacy-1"]'),
        viewer.querySelector('[data-link="legacy-2"]'),
        viewer.querySelector('[data-link="legacy-3"]')
      ],
      split: [
        viewer.querySelector('[data-link="split-1"]'),
        viewer.querySelector('[data-link="split-2"]'),
        viewer.querySelector('[data-link="split-3"]')
      ]
    };

    const content = {
      legacy: {
        caption: 'Original architecture: the launcher, system binary, and user-facing permission story could diverge, which made failure analysis harder than it needed to be.',
        steps: {
          1: {
            title: 'How a key press enters the legacy system',
            copy: 'The app launches a service path, but the long-lived runtime identity moves from the launcher to a separate installed binary. That handoff is where mental models start to drift.',
            notes: [
              'The process launch path and the process users grant trust to were not guaranteed to stay aligned.',
              'A novice engineer had to understand both the launcher and the installed binary to reason about one key press.',
              'Upgrades could preserve registration while still leaving the effective runtime path confusing.'
            ],
            outcome: 'Ambiguity at startup makes every later health signal harder to interpret.',
            highlightNodes: ['legacy.app', 'legacy.launcher'],
            highlightLinks: ['legacy.0']
          },
          2: {
            title: 'Legacy input capture',
            copy: 'The installed binary becomes the HID-owning runtime. That means input capture depends on a path that is no longer the same as the initial launch identity.',
            notes: [
              'Input Monitoring is about the process that actually opens keyboard devices.',
              'A launch handoff can leave permission guidance pointing at the wrong conceptual owner.',
              'This is why a system can look “green” while built-in capture is still effectively wrong.'
            ],
            outcome: 'Permission truth and runtime truth were too easy to separate by accident.',
            highlightNodes: ['legacy.launcher', 'legacy.kanata'],
            highlightLinks: ['legacy.1']
          },
          3: {
            title: 'Legacy remapping path',
            copy: 'Kanata still performs the remapping work, but the same runtime path also carries output readiness decisions and recovery assumptions.',
            notes: [
              'There was no clean seam between remapping logic and platform-specific output concerns.',
              'That made the runtime harder to host differently on macOS.',
              'A single daemon ended up owning too many responsibilities.'
            ],
            outcome: 'The system worked, but its responsibilities were too entangled.',
            highlightNodes: ['legacy.kanata'],
            highlightLinks: ['legacy.1']
          },
          4: {
            title: 'Legacy output path',
            copy: 'The same runtime path that captured input also had to touch pqrs VirtualHID readiness and output emission. That is where the user-session and privileged models collided.',
            notes: [
              'A user-session host could still fail because output ownership was not isolated cleanly.',
              'The runtime could hit root-sensitive state before alternate output ownership had a chance to take over.',
              'This is the key macOS mismatch the split runtime resolves.'
            ],
            outcome: 'Input and output were coupled through a boundary they should not have shared.',
            highlightNodes: ['legacy.kanata', 'legacy.vhid'],
            highlightLinks: ['legacy.2']
          },
          5: {
            title: 'Legacy recovery story',
            copy: 'Because registration, liveness, capture readiness, and output health were entangled, recovery logic risked over-trusting metadata such as “service enabled.”',
            notes: [
              'A registered service is not the same thing as a healthy runtime.',
              'Recovery needed stronger postcondition checks than metadata alone could provide.',
              'The architecture itself was pushing the code toward false positives.'
            ],
            outcome: 'The old design made “is it actually working?” a more expensive question than it should be.',
            highlightNodes: ['legacy.app', 'legacy.kanata', 'legacy.vhid'],
            highlightLinks: ['legacy.0', 'legacy.1', 'legacy.2']
          }
        }
      },
      split: {
        caption: 'New split runtime: input capture stays in a stable app-owned host identity, while privileged output moves behind a narrow bridge.',
        steps: {
          1: {
            title: 'How a key press enters the new system',
            copy: 'The app still coordinates startup, but it now prepares a bridge session and launches a bundled host whose identity remains stable through input capture.',
            notes: [
              'The app remains the orchestration layer, not the raw input runtime.',
              'The host is the durable owner of the input side of the flow.',
              'This makes the runtime graph easier to explain to new contributors.'
            ],
            outcome: 'The permission story now starts with the same process graph the architecture actually uses.',
            highlightNodes: ['split.app', 'split.host'],
            highlightLinks: ['split.0']
          },
          2: {
            title: 'User-session input capture',
            copy: 'The bundled runtime host is the process that opens HID devices and owns the app-bundled identity macOS associates with Input Monitoring.',
            notes: [
              'The HID-owning process and the permission-bearing identity are now intentionally the same.',
              'No launcher exec handoff is needed to explain who owns input.',
              'This is the biggest usability and debuggability win.'
            ],
            outcome: 'Permission guidance, diagnostics, and runtime behavior now point to the same conceptual owner.',
            highlightNodes: ['split.host'],
            highlightLinks: ['split.0']
          },
          3: {
            title: 'Remapping stays with Kanata',
            copy: 'The host still runs the Kanata runtime and preserves the cross-platform remapping core. The change is in hosting and output transport, not in replacing the engine.',
            notes: [
              'KeyPath is not rewriting Kanata’s parser or state machine.',
              'The split runtime is a hosting strategy, not a new remapping algorithm.',
              'That keeps the architecture ambitious without becoming a rewrite.'
            ],
            outcome: 'The codebase gets cleaner macOS boundaries without throwing away proven remapping logic.',
            highlightNodes: ['split.host'],
            highlightLinks: ['split.1']
          },
          4: {
            title: 'Privileged output is isolated',
            copy: 'Once remapped events are ready, the host forwards them over a narrow protocol to the privileged output bridge. The bridge owns the root-scoped VirtualHID path.',
            notes: [
              'The host no longer needs to be the same process that crosses the privileged output boundary.',
              'The bridge protocol can stay small: handshake, emit, modifier sync, reset, and health.',
              'Small privilege seams are easier to secure and recover.'
            ],
            outcome: 'Input and output now cross the privilege boundary intentionally instead of implicitly.',
            highlightNodes: ['split.host', 'split.bridge', 'split.vhid'],
            highlightLinks: ['split.1', 'split.2']
          },
          5: {
            title: 'Recovery and verification',
            copy: 'Because the pieces are explicit, recovery can restart the companion, rehydrate sessions, and verify real runtime readiness instead of guessing from service metadata.',
            notes: [
              'InstallerEngine and runtime coordinators can verify postconditions component by component.',
              'PermissionOracle remains the source of permission truth; the bridge does not take over that responsibility.',
              'This is better software engineering because each subsystem reports on what it truly knows.'
            ],
            outcome: 'The new architecture is easier to inspect, easier to recover, and harder to fool with false success.',
            highlightNodes: ['split.app', 'split.host', 'split.bridge', 'split.vhid'],
            highlightLinks: ['split.0', 'split.1', 'split.2']
          }
        }
      },
      diff: {
        caption: 'What changed: the key architectural move is separating user-session input ownership from privileged output ownership while keeping orchestration centralized in the app.',
        steps: {
          1: {
            title: 'The startup graph became explicit',
            copy: 'In diff mode, read left to right. The old side shows a launcher handoff into a system binary. The new side replaces that with a stable bundled host and a prepared bridge session.',
            notes: [
              'The old side optimizes for a single-daemon story.',
              'The new side optimizes for matching macOS trust boundaries.',
              'That is a better long-term trade for a macOS app.'
            ],
            outcome: 'The system graph is slightly richer, but much more honest.',
            highlightNodes: ['legacy.launcher', 'legacy.kanata', 'split.host'],
            highlightLinks: ['legacy.1', 'split.0']
          },
          2: {
            title: 'Input ownership moved',
            copy: 'The most important change is not that there are more processes. It is that the process opening HID devices is now the one with the stable app-owned identity.',
            notes: [
              'This removes the biggest source of permission confusion.',
              'It aligns onboarding, runtime behavior, and diagnostics.',
              'Novice developers can now answer “who owns input?” in one sentence.'
            ],
            outcome: 'Good architecture often means making the right thing obvious.',
            highlightNodes: ['legacy.kanata', 'split.host'],
            highlightLinks: ['legacy.1', 'split.0']
          },
          3: {
            title: 'Remapping stayed put',
            copy: 'The Kanata core remains the remapping engine in both designs. The change is the shell around it: hosting, bridging, and health ownership.',
            notes: [
              'This avoids turning the refactor into a rewrite.',
              'It keeps the system modular and easier to validate incrementally.',
              'The architecture change is substantial without being wasteful.'
            ],
            outcome: 'Reuse the strong core; refactor the unstable edges.',
            highlightNodes: ['legacy.kanata', 'split.host'],
            highlightLinks: ['legacy.1', 'split.1']
          },
          4: {
            title: 'Output ownership moved out',
            copy: 'Output is now an explicit bridge boundary rather than an implicit side effect of the same runtime path that owns input. This is the cutover’s central split.',
            notes: [
              'The bridge gives privileged output its own lifecycle and diagnostics.',
              'The host can focus on input capture and Kanata processing.',
              'That separation reduces cross-boundary surprise.'
            ],
            outcome: 'One responsibility per boundary is easier to make reliable.',
            highlightNodes: ['legacy.vhid', 'split.bridge', 'split.vhid'],
            highlightLinks: ['legacy.2', 'split.1', 'split.2']
          },
          5: {
            title: 'Verification got stronger',
            copy: 'The new design reinforces an important engineering rule: registration is not liveness. Runtime health must be proven with process evidence and real readiness checks.',
            notes: [
              'This fits the repo’s service lifecycle invariants directly.',
              'It is a good example of architecture and operational correctness reinforcing each other.',
              'A clearer graph produces clearer tests.'
            ],
            outcome: 'The cutover improves both runtime behavior and the team’s ability to reason about it.',
            highlightNodes: ['legacy.app', 'legacy.kanata', 'split.app', 'split.host', 'split.bridge'],
            highlightLinks: ['legacy.0', 'legacy.1', 'split.0', 'split.1']
          }
        }
      }
    };

    let currentView = 'legacy';
    let currentStep = 1;
    let replayTimer = null;

    function allDiagramItems() {
      return [
        ...Object.values(nodes.legacy),
        ...Object.values(nodes.split),
        ...links.legacy,
        ...links.split
      ].filter(Boolean);
    }

    function parseTarget(target) {
      const [family, key] = target.split('.');
      if (family === 'legacy' || family === 'split') {
        return nodes[family][key] || links[family][Number(key)];
      }
      return null;
    }

    function setActiveButton(buttons, activeValue, attributeName) {
      buttons.forEach((button) => {
        const isActive = button.dataset[attributeName] === String(activeValue);
        button.classList.toggle('is-active', isActive);
        button.setAttribute('aria-selected', isActive ? 'true' : 'false');
      });
    }

    function render() {
      const state = content[currentView].steps[currentStep];
      setActiveButton(viewButtons, currentView, 'cutoverView');
      setActiveButton(stepButtons, currentStep, 'cutoverStep');

      allDiagramItems().forEach((item) => {
        item.classList.remove('is-highlighted', 'is-active');
        item.classList.add('is-dimmed');
      });

      state.highlightNodes.forEach((target) => {
        const item = parseTarget(target);
        if (item) {
          item.classList.remove('is-dimmed');
          item.classList.add('is-highlighted');
        }
      });

      state.highlightLinks.forEach((target) => {
        const item = parseTarget(target);
        if (item) {
          item.classList.remove('is-dimmed');
          item.classList.add('is-active');
        }
      });

      phaseLabel.textContent = `Step ${currentStep}`;
      phaseTitle.textContent = state.title;
      phaseCopy.textContent = state.copy;
      phaseNotes.innerHTML = state.notes.map((note) => `<li>${note}</li>`).join('');
      outcomeTitle.textContent = 'Engineering payoff';
      outcomeCopy.textContent = state.outcome;
      caption.innerHTML = `<strong>${currentView === 'legacy' ? 'Original architecture' : currentView === 'split' ? 'New split runtime' : 'Diff view'}:</strong> ${content[currentView].caption}`;
    }

    function stopReplay() {
      if (replayTimer) {
        window.clearInterval(replayTimer);
        replayTimer = null;
      }
    }

    viewButtons.forEach((button) => {
      button.addEventListener('click', () => {
        stopReplay();
        currentView = button.dataset.cutoverView;
        render();
      });
    });

    stepButtons.forEach((button) => {
      button.addEventListener('click', () => {
        stopReplay();
        currentStep = Number(button.dataset.cutoverStep);
        render();
      });
    });

    replayButton.addEventListener('click', () => {
      stopReplay();
      currentStep = 1;
      render();
      replayTimer = window.setInterval(() => {
        currentStep = currentStep === 5 ? 1 : currentStep + 1;
        render();
      }, 1800);
      window.setTimeout(stopReplay, 9000);
    });

    render();
  })();
</script>
