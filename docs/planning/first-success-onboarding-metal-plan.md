# First-success onboarding and Metal keyboard stage plan

**Status:** In progress

**Scope:** KeyPath’s optional post-setup onboarding, its catalog integration, and a reusable Metal keyboard scene for a later overlay adoption.

## Decision

Build the experience in two deliberate passes:

1. **Functional, catalog-backed onboarding.** Build the complete behavior first: a calm, accessible flow that teaches real value, installs the same catalog features exposed elsewhere in KeyPath, and proves that each change is safe and reversible. Its SwiftUI keyboard stage is a deliberately simple development scaffold and permanent accessibility fallback, not the intended final visual treatment.
2. **Metal keyboard stage.** Deliver the final visual experience: a large, elegant, interactive keyboard composition whose physical key motion carries the story of each lesson. Its scene model will be designed for later reuse by the live keyboard overlay, but overlay adoption is a separate, measured follow-up.

Metal is not a replacement for the SwiftUI application UI. SwiftUI continues to own window chrome, text, controls, accessibility, focus, localization, and every product decision. Metal is the hero stage of the final onboarding: it owns the tactile keyboard composition, material depth, pressed response, highlights, and the spatial transformation between keyboard states. This is not a decorative shader behind an ordinary wizard.

## Product contract

The onboarding is an optional invitation after a healthy first setup, not an installation step. It must answer four questions before asking anyone to change a key:

1. What everyday friction does this solve?
2. Why is this particular key a good candidate?
3. What changes, and what is the tradeoff?
4. Where can it be changed or undone later?

The recommended path is:

1. **Reclaim a nearby key.** Explain that Escape dismisses small UI such as menus, popovers, and search; it is useful often but far away. Explain that Caps Lock is nearby and often unused. Offer an explicit skip to people who use Caps Lock for capitalization.
2. **Create a clean shortcut prefix.** Keep tap-for-Escape, then explain why holding the same key is useful before introducing “Hyper” as Control + Option + Shift + Command. Existing apps rarely reserve the full combination, so it is a clean prefix for shortcuts the person chooses.
3. **Put a favorite app on a letter.** Teach the gesture—hold Caps Lock and press a chosen letter—without inventing an app or key on the person’s behalf. Let them choose both the app and letter, then save, verify, and try the real shortcut without leaving onboarding.
4. **Continue in Rules.** Only after all three wins are complete, hand off to Rules with Quick Launcher focused so the person can manage what they made and discover further remapping. Do not send a new user to an undifferentiated store grid.

Every guided feature follows the same interaction contract:

`motivation → preview → explicit choice → apply and verify → try it → keep the result visible → continue or stop`

After the third win, one final handoff shows where the completed configuration
lives and opens the broader discovery surface.

## Final visual bar

The final experience should feel like a compact, responsive piece of product cinema: one calm physical world, with the person’s real choice causing each transformation. It should be remarkable because the interaction is precise and consequential, not because the screen continuously performs.

The keyboard stage occupies the visual center of each learning moment. Copy sits around it with enough space to explain the why; it never competes with a dashboard, card grid, or installer chrome.

### Caps Lock → Escape

1. A full keyboard settles into view with a quiet, tangible material depth. The Caps Lock key carries a subtle focus edge; no decorative idle loop runs.
2. The motivation describes a familiar escape problem. A small representative menu/popover appears in the same spatial world, reinforcing what Escape does without asking the person to read a manual.
3. On explicit approval, Caps Lock responds instantly as a real key: it compresses, its material catches light, and its virtual legend resolves from its old role into `esc`. A short positional echo makes the new role legible without a literal arrow or particle effect.
4. The key releases into a calm installed state. When the person presses their physical Caps Lock key during practice, the virtual key responds in synchrony whenever safe observation is available.
5. The installed Escape state remains visible as the person continues. Its matching Rules configuration is revealed only in the final discovery/management handoff, after all three wins are complete.

### Hold Caps Lock for Hyper

1. The installed Caps Lock key becomes the anchor for the next lesson; nothing resets or re-explains the first win.
2. As the person holds it, its surface depresses and four restrained modifier marks gather into one coherent state. The visual teaches “one held key prepares a shortcut” before it calls that state Hyper.

### Hyper plus a chosen letter

1. Hyper remains visibly anchored to held Caps Lock while a restrained group of letter keys becomes available; the onboarding never pretends that an unchosen letter or app is already configured.
2. Inline Quick Launcher controls let the person choose an actual app and letter. Saving applies and verifies that exact mapping before the stage presents it as complete; cancelled selection or reload failure remains in onboarding with a clear recovery path.
3. After the person tries the shortcut, the final handoff opens Rules with Quick Launcher focused. The selected app, letter, and editable mapping are visible there, while nearby remaps feel like possibilities connected to the keyboard journey rather than a store taking over the flow.

Motion is tightly choreographed: immediate response at pointer/key down; roughly 0.35–0.55 seconds for a meaningful key transformation; no more than one major visual event for each user decision. It is interruptible at every point, uses the same object and path when reversing, and reduces to color/opacity feedback for Reduce Motion. Sound, confetti, and perpetual ambient movement are explicitly out of scope.

The keyboard's one-time entrance establishes that physical world before the
first lesson: the dialog opens as a still, dark room with MacBook-like backlit
legends, holds for 1.5 seconds after the first keyboard frame is actually
presented, then a broad feathered light enters from the keyboard side and
resolves the whole window into the reference-light design. The illumination is
directional but never a hard UI wipe; Metal gives individual key surfaces a
small spatial response while native SwiftUI owns the matching window palette.
Reduce Motion keeps the same hold and a short uniform color resolve without the
traveling light front.

The entrance is a bounded proof gate for Metal, not an open-ended visual-effects
project. The forced-Metal installed-app capture must demonstrate all of the
following in the 1.5-second dark hold and one approximately 0.55-second
directional reveal:

- convincing dark graphite key materials with neutral, MacBook-like emitted
  legends rather than blue gaming-keyboard glow;
- one continuous, broad light front shared by the Metal keyboard and native
  window palette, visibly crossing individual key surfaces without becoming a
  hard wipe;
- per-pixel bevel, contact-shadow, diffuse, and restrained specular response
  that gives the keycaps physical depth as the front passes; and
- a clean, reference-light settled frame with no residual bloom, muddy overlay,
  foreground flash, or mismatch between the Metal and SwiftUI portions of the
  dialog.

Implement only the smallest rendering work needed to prove that bar: a shared
window-space light-front model, analytic keycap surface response in the fragment
shader, and a cached legend mask/atlas for real backlight emission while the
native semantic overlay continues to own accessibility and interaction. Keep
the renderer demand-driven and stop drawing after the entrance settles. Review
dark-hold and 25/50/75/100-percent reveal frames from the deployed, reopened app,
not previews or build output. If that installed capture does not materially beat
the SwiftUI baseline in physical depth, illumination, and cinematic coherence,
Metal has failed the proof: SwiftUI remains the default and further Metal work
stops.

## Pass 1 — Functional SwiftUI-first onboarding

### 1. Establish one canonical catalog installation path

The current first-success controller toggles `capsLockRemap` and `launcher` collections directly. That produces the behavior, but it bypasses the catalog’s `PackInstaller` record and therefore its installed-state, ownership, conflict, dependency, and future-migration contract.

Add a small application-facing catalog installation facade rather than teaching the onboarding view about pack internals. Its responsibilities are:

- accept an explicit, typed feature selection for Caps Lock tap = Escape and Caps Lock hold = Hyper;
- resolve the catalog pack by stable ID (`Caps Lock Remap` and `Quick Launcher`);
- apply the selected collection configuration and enable the collection as one logical operation;
- use `PackInstaller`/`InstalledPackTracker` as the authority for installed state and conflicts;
- batch configuration generation and reload so a feature does not visibly “half install”;
- return a typed result: installed, already-installed-with-same-choice, needs-user-choice, recoverable failure, or unavailable.

For collection-backed packs, extend the installer contract to support a typed configuration override in the same transaction as the collection enablement. Do not install a pack, write a second direct mutation, and hope the two reloads and tracker state remain aligned. The tracker record should be written only after the configuration is durable; a failed or cancelled operation must leave the prior collection and tracker state intact.

The onboarding must use this facade for every recommended catalog feature. A direct collection mutation should remain an editor-level operation, not a first-success shortcut.

### 2. Introduce an explicit onboarding session model

Create a narrowly scoped `@MainActor @Observable` session model, separate from the broad `KanataViewModel`. It owns only presentation state and receives narrow, typed facts from the catalog facade:

- entry reason and eligibility;
- selected path and current guided feature;
- current learning moment;
- apply/practice/reveal status;
- recoverable errors and retry state;
- whether the user has deferred, completed, or should later resume the optional experience.

Keep durable setup state in the rule collections and installed-pack tracker. Persist only the minimum onboarding resume/defer state in user defaults; never persist an in-progress visual animation as product state. The view should not infer installed state from a progress indicator or from an optimistic button tap.

Add a narrow routing policy that receives the current rule collections and installed packs. It must:

- skip Caps Lock when it is already meaningfully configured or the user declines it;
- avoid suggesting a feature that conflicts with an installed pack;
- recognize Quick Launcher conflicts and resolve or safely skip them within onboarding rather than opening Rules mid-flow;
- produce a safe alternate path rather than stopping the experience;
- focus the catalog handoff on the same Quick Launcher collection, so the final screen and Rules cannot drift apart.

### 3. Rebuild the flow around learning moments, not wizard pages

Replace the fixed left rail and `Step 1 of 4` treatment. Those are appropriate for installation but make an optional learning path feel compulsory.

Compose the dialog from small, separate SwiftUI view types with narrow inputs:

- a quiet progress header for the three escalating wins and Rules handoff;
- a benefit-led lesson copy column that explains the why before the action;
- one persistent keyboard hero shared across every moment;
- a Caps Lock practice control that tests the real Escape behavior;
- inline app and letter controls that save the real Quick Launcher mapping while preserving or clearly resolving existing configuration.

Use standard KeyPath/macOS controls and the existing action-bar treatment. Every interactive control needs an accessibility identifier. The window remains normally closable and keyboard-operable; the person can stop at any point without having to reverse a change first.

All new visible copy belongs in the string catalog. Non-view recommendation/copy models carry `LocalizedStringResource`, not prematurely resolved `String` values. Layout uses semantic leading/trailing alignment and adapts to longer translations.

### 4. Implement a real practice loop

The product’s strongest moment is pressing the actual changed key. That cannot be faked by a success animation that runs immediately after “Apply.”

Build a `PracticeCoordinator` with three supported outcomes:

- **Observed success:** reuse an existing, privacy-safe KeyPath/Kanata input signal when one can prove that the expected input or action happened.
- **Self-confirmed success:** if KeyPath cannot observe that interaction reliably in the current focus context, invite the person to try it and let them continue without a false error or an unbounded wait.
- **Needs help:** if apply/reload failed, show a concise error and a direct retry, keep-current, or skip-this-win path within onboarding. Do not present the feature as installed or open Rules before the final handoff.

The coordinator never installs a global event monitor just to make onboarding look smart. It does not capture or store arbitrary keystrokes. Its success state is independent from visual motion: the configuration must save and reload successfully before the visual stage settles into the installed state.

### 5. Define the SwiftUI functional stage

The first implementation uses native SwiftUI to prove state transitions, application/reload behavior, accessibility, content hierarchy, and actual practice before GPU work begins. It is a development baseline and permanent fallback for accessibility, screenshots, and Metal-unavailable situations; it is **not** visual sign-off for the final onboarding.

Use a small set of named motion roles rather than unrelated duration literals:

- **Press:** immediate key compression and active tint on pointer-down; short, critically damped return.
- **Transformation:** a source keycap relabels and changes role along a single spatial path; the output key never looks like an arrow.
- **Reveal:** the same key’s accent and geometry lead into the matching inline choice or practice control.
- **Handoff:** after all three wins, the selected key and app remain spatially connected as Rules becomes the final management and discovery surface.
- **Completion:** one restrained confirmation pulse after durable apply; no confetti, loop, or sound effect.

Default motion is critically damped (approximately 0.3–0.4 seconds) with no ornamental overshoot. Motion begins at the object that caused it, can be interrupted by Back, Skip, or Close, and never locks out controls while it completes. Reduce Motion substitutes short opacity and color transitions; reduced transparency and increased contrast receive separate visual treatment.

The SwiftUI keyboard stage initially reuses KeyPath’s existing keycap roles, geometry, colors, and selected physical layout. It should be a contained, testable `KeyboardStageRendering` implementation, not a second keyboard design system.

### 6. Make state, safety, and recovery visible

Before a change, explain its tradeoff in ordinary language. After each change, keep the installed result visible in onboarding. At the final handoff, make every installed feature visible in Rules and show where it can be changed. Add a single, obvious undo affordance where it is safe to restore the exact previous configuration.

Handle these states intentionally:

- existing Caps Lock behavior or an installed Caps Lock pack;
- a conflicting catalog feature;
- app selection cancelled or unavailable;
- an unavailable window-management prerequisite;
- config write/reload failure;
- window close, defer, and later resume;
- first setup that becomes unhealthy while the experience is open.

No action should silently replace another mapping. Any conflict choice should describe the outcome (“keep your current shortcut” or “use the new shortcut”) rather than implementation terms such as collection, pack, or dependency.

### 7. Functional test and review gate

Add focused tests before the Metal work begins:

- catalog-backed install records are written for each onboarding-installed feature;
- selected Caps Lock and launcher settings reach the same durable configuration as catalog installation;
- installation is atomic across tracker/config failure paths;
- routing policy preserves existing Caps Lock and Quick Launcher configurations, keeps all three wins inline, and opens the correct Rules controls only at the final handoff;
- onboarding eligibility, defer/resume, and close behavior;
- apply errors never advance the learning moment;
- reduce-motion and accessibility labels/identifiers;
- snapshot coverage for the invitation, each motivation state, conflict state, practice state, and catalog handoff;
- installed-app manual QA: clean setup, an existing user, a keyboard user with preexisting rules, light/dark, larger text, VoiceOver, and Reduce Motion.

The functional pass is complete only when a person can install a catalog feature, practice it, find it later in the catalog/Rules, and safely stop or recover at every point. It unlocks Metal work; it does not claim the final visual experience is complete.

## Pass 2 — Reusable Metal keyboard stage

### 8. Prove the packaging and rendering seam first

Before migrating a screen, create a small technical spike that proves Metal shaders can be compiled, packaged, loaded, and snapshot-tested from the existing Swift Package macOS 15 application target. Do not rely on an Xcode-only build phase that the canonical package build will not execute.

Add a renderer boundary that the SwiftUI flow can select at runtime:

- `KeyboardStageScene` — pure, `Equatable` visual data: layout geometry, key instances, labels, role/accent, pressure, transform progress, reveal target, and display-accessibility mode.
- `KeyboardStageRendering` — a lightweight SwiftUI-facing protocol/view boundary with the same scene input for the existing SwiftUI fallback and the Metal implementation.
- `KeyboardStageClock` — injectable time source for deterministic scene tests and previews.

Business logic, catalog state, copy, focus, and user input do not enter the renderer. They produce a scene; the renderer draws it. This boundary is what makes later overlay reuse realistic rather than aspirational.

### 9. Make Metal the keyboard experience

Embed one `MTKView` inside an AppKit/SwiftUI bridge for the keyboard stage only. That stage is large enough to be the visual center of every learning moment; the rest of the dialog remains native SwiftUI so the keyboard world can be beautiful without sacrificing native interaction and accessibility.

The first renderer draws:

- a full physical keyboard or focused key region using the selected KeyPath layout;
- instanced rounded keycaps with consistent continuous corners, material depth, and soft shadows;
- active, pressed, installed, and recommended color roles;
- the Caps Lock-to-Escape spatial transform, with a subtle positional echo and a destination glow;
- a restrained Rules/catalog-horizon transition reserved for the final handoff.

Use instanced quads plus a rounded-rectangle signed-distance-field fragment treatment for the keycap surfaces. This gives crisp scalable edges, consistent corner treatment, and inexpensive per-key depth/highlight changes without generating individual textures or views for every keycap.

Keep text semantic and accessible. For the photorealistic entrance proof, render visual key legends from a cached mask/atlas so Metal can produce convincing backlight emission, while transparent native SwiftUI/AppKit elements keyed from the same geometry remain the authority for accessibility and interaction. Do not make shader-rendered labels the sole semantic representation.

### 10. Make the renderer demand-driven and respectful

Metal must not create a permanent render loop for a mostly static onboarding window.

- Keep the `MTKView` paused while the stage is static, hidden, unfocused, minimized, or offscreen.
- Render only after a scene change and during a bounded active animation interval.
- Prefer the display’s natural cadence while active; target smooth 60 Hz everywhere and take advantage of 120 Hz displays when available, without treating 120 Hz as a correctness requirement.
- Stop animation immediately on Reduce Motion, close, backgrounding, or a rendering error.
- Fall back to the SwiftUI stage if `MTLCreateSystemDefaultDevice()` fails, the renderer cannot load, or accessibility settings choose the simplified treatment.

Do not use a compute shader, particle system, live blur field, or motion blur in the first pass. They do not clarify the product lesson. The visual signature is crisp physical key motion, deliberate material depth, and transformations that stay attached to the person’s choice—not GPU spectacle.

### 11. Preserve interaction and accessibility above the GPU layer

`MTKView` should be treated as visual output, not as the sole interactive/control tree.

- SwiftUI owns buttons, focus order, tooltips, VoiceOver labels, and keyboard shortcuts.
- Provide a semantic accessibility representation of the highlighted key, its prior role, its new role, and the current practice instruction.
- Use the same scene model for the visual renderer and accessibility descriptions so they cannot drift.
- Give pointer interaction a native hit target above the renderer; pressed state is forwarded to the scene immediately.
- Keep the text and control layout usable at larger text sizes; if the screen cannot fit a full stage, reflow or use a focused key region instead of clipping.

### 12. Integrate Metal only after parity

Integrate the Metal stage behind a developer/QA feature flag first. The SwiftUI renderer remains selectable for screenshots and comparison.

For each learning moment, compare side by side:

- static initial state;
- press state;
- transformation at early, middle, and settled progress;
- reduce-motion state;
- light/dark, increased-contrast, and reduced-transparency states;
- narrow and large-text window sizes.

Switch the onboarding default to the Metal stage only after the deployed, reopened app passes the bounded entrance proof, is visually consistent with KeyPath’s existing keycap vocabulary, keeps motion causal and interruptible, and exercises the fallback path. The visual review bar is not merely “works on GPU”: the installed capture must feel materially more physical, elegant, and coherent than the SwiftUI baseline. If it does not, keep SwiftUI as the default and stop further Metal investment.

### 13. Reuse in the live keyboard overlay as a separate follow-up

After the onboarding renderer is stable, open a dedicated overlay adoption task. Reuse `KeyboardStageScene`, key geometry, roles, shader pipeline, and demand-driven scheduling. Do not force the onboarding sequence model, copy, or dialog controls into the overlay.

The overlay task should add its own requirements:

- live input-state ingestion and coalescing;
- multi-layout and resize behavior;
- independent overlay accessibility behavior;
- CPU/GPU profiling under real typing;
- safeguards for persistent rendering and battery/thermal cost;
- compatibility with current overlay drag, inspector, and diagnostics behavior.

This sequencing creates a shared visual engine without coupling two products before either one has proven its own interaction model.

## Delivery slices

1. **Catalog-backed install contract.** Add the typed onboarding/catalog facade, transactional collection override, tracker parity, and unit tests. No visual redesign yet.
2. **Functional experience.** Replace the fixed step wizard with the invitation, motivation, choice, practice, reveal, and catalog handoff. Use the temporary SwiftUI stage and ship all behavior/accessibility tests.
3. **Functional review.** Deploy the installed app, exercise clean and existing-user paths, and revise copy/interaction from real use. This stabilizes the story that Metal will animate; it is not final visual approval.
4. **Metal spike.** Prove package integration, scene model, fallback selection, and deterministic scene test harness behind a flag.
5. **Metal onboarding stage.** First pass the bounded photorealistic entrance proof in an installed-app capture. Only then implement the full hero-stage composition and the Caps Lock, Hyper/launcher, next-win, and final catalog-horizon sequences; perform side-by-side design QA, accessibility QA, and performance profiling before enabling Metal as the default. Otherwise retain SwiftUI as the default and stop.
6. **Overlay adoption.** Separate feature/PR after onboarding is stable; reuse the renderer core but validate overlay-specific behavior independently.

## Completion criteria

The project is successful when a person who knows nothing about keyboard remapping can understand why a change is useful, choose it safely, feel the real keyboard behavior work, find the same installed capability in the catalog later, and stop or change course without fear.

The Metal pass is successful only when the physical key transformation makes the onboarding feel elegant, alive, and unmistakably premium—not merely more coherent than the SwiftUI baseline—without losing accessibility, testability, battery discipline, or the ability to fall back safely.
