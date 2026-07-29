# First-success onboarding design QA

## Source visual truth and evidence

- Source: `/Users/malpern/Downloads/Generated image 1 (2).png`
- Installed dark-hold capture: `/tmp/keypath-onboarding-legends-final-verified-dark.png`
- Installed settled-light capture: `/tmp/keypath-onboarding-legends-final-verified-light.png`
- Full-view comparison: `/tmp/keypath-onboarding-legends-final-comparison.png`
- Focused keyboard comparison: `/tmp/keypath-onboarding-legend-focus-comparison.png`

## Viewport and state normalization

- Source pixels: 1506 x 1045.
- Implementation pixels: 1920 x 1364, captured from the installed 960 x 682-point window at 2x density with window shadow omitted.
- Full-view comparison: each complete window is aspect-fit into a 900 x 650 panel. No surrounding desktop or window shadow is included.
- Focused comparison: the keyboard regions are cropped using normalized window coordinates and rendered into equal 900 x 680 panels.
- State: first Caps Lock lesson, initial 1.5-second dark hold, Metal enabled. The settled-light endpoint was captured separately after the directional light rise.
- Installed artifact: `/Applications/KeyPath.app` launched through Help > Replay KeyPath Tour.

## Findings

No actionable P0, P1, or P2 mismatch remains in the reviewed state.

- Fonts and typography: both use the native macOS system family and the same left-aligned hierarchy. Keyboard legends now use explicit macOS light faces for physical keys, lowercase functional labels, uppercase letters, equally weighted shifted/unshifted number-row pairs, and a stacked Command symbol/name. The implementation keeps slightly stronger instructional body contrast for accessibility. The longer benefit copy and specific action label are intentional product requirements, not visual drift.
- Spacing and layout rhythm: the title, feature rows, divider, footer actions, keyboard entry edge, and deck mass now align with the reference. The Caps camera uses restrained horizontal magnification so the key size matches without cropping the top or bottom rows.
- Colors and visual tokens: the near-black left field, warm right-side graze, graphite deck, white legend apertures, KeyPath blue, and exact light endpoint are aligned. The settled light view keeps softer wells instead of carrying the dark contact occlusion into daylight.
- Image and material quality: the Metal hero now separates the deck, recessed wells, contact occlusion, cast penumbra, key skirts, crowned key faces, microfacet response, procedural graphite/aluminum grain, directional backlight, and a concentrated white-blue Caps bevel catch. No raster texture or decorative approximation is used.
- Copy and content: copy remains benefit-led and task-specific. `Skip tour` and `Use Caps Lock for Escape` intentionally replace the reference's generic `Skip` and `Continue`.

## Comparison history

1. P1 — The baseline keyboard read as flat rounded rectangles with uniform cyan-gray perimeter light. Fixed with separate key wells, contact and area shadows, directional diffuser exposure, GGX material response, and localized lesson-key emission. Post-fix evidence: focused keyboard comparison.
2. P2 — Legends initially used generic UI typography rather than MacBook-like optical proportions. Fixed by using explicit macOS light faces and sizing the atlas so ordinary legends resolve to roughly 28% of the keycap height. Post-fix evidence: focused keyboard comparison.
3. P2 — The keyboard occupied too little of the dialog and showed too many columns. Fixed with an anisotropic Caps camera that increases horizontal presence while preserving vertical context. Post-fix evidence: full-view comparison.
4. P2 — The zoomed composition clipped the deck's rounded leading corner and first-column keys. Fixed by moving the Caps viewport focus left and lowering its vertical bias. Post-fix evidence: full-view and focused comparisons.
5. P2 — Light-mode wells retained overly hard dark rims. Fixed by independently reducing settled well, skirt, contact-shadow, and cast-shadow strength. Post-fix evidence: settled-light capture.
6. P2 — Keyboard legends omitted shifted number-row symbols, capitalized `Tab`, and rasterized selected/function legends too heavily. Fixed in the shared scene model and both render paths: lowercase functional labels, uppercase letters, paired symbols (`~`/`` ` ``, `!`/`1`, `@`/`2`, and so on), equal-size number-row stacking, and explicit macOS light font faces. Post-fix evidence: full-view and focused keyboard comparisons.

## Follow-up polish

- P3 — The generated reference uses slightly irregular, painterly highlights. The implementation stays deterministic and physically coherent, so exact per-pixel highlight placement differs while preserving the same lighting direction and depth hierarchy.
- P3 — Window traffic-light state varies with focus during automated capture and is outside the onboarding content hierarchy.

## Iteration 2 — directional-light pass

An independent installed-app review against the source image found the remaining
gap concentrated in one theme: the reference's light is directional while the
implementation's was symmetric. This pass addressed that in the Metal fragment
shader and the shared entrance model, verified from fresh installed replays.

- Directional rims: every additive edge term (bevel specular, lower bevel
  catch, inner rim, emphasis bevel, accent stroke) now follows a
  light-facing mask during the dark hold, so keycap rims catch on the upper
  right and fall away on the far side instead of outlining evenly. The lesson
  key's dark-room rim resolves toward white with the blue halo outside,
  matching the reference's bevel-catch grammar.
- Deck graze: the warm sweep reaches further left, roughly doubles in
  strength, and pools through a large-scale noise mask so the aluminum reads
  as a photographed area light rather than a uniform tint.
- Wells and shadows: dark-hold well envelopes widen and contact/cast shadows
  deepen (entrance only — the settled light state keeps its original softer
  weights), grounding each cap in a visible cavity.
- Legend field response: aperture brightness and warmth now vary along the
  light axis (a ±20% spatial emission scale in the legend fragment), replacing
  the perfectly even backlight panel.
- Physical press: a pressed cap now darkens toward its lower edge and catches
  light on its top bevel instead of only swapping to a flat accent fill.
- Reveal pacing: the light front's travel is eased (`pow(progress, 1.9)`), so
  roughly 60% of the 0.75 s reveal crosses the keyboard span; a capture burst
  now lands multiple frames of the feathered front crossing individual
  keycaps, where the linear sweep previously crossed them in ~0.28 s.
- Lesson copy overflow: the copy column shows a bottom fade whenever content
  overflows and the reader is not at the bottom, so the launcher step's third
  benefit row no longer appears clipped mid-sentence with no affordance.

Evidence (installed replay, window-server capture):

- Dark hold: `/tmp/keypath-onboarding-directional-dark.png`
- Front crossing keycaps: `/tmp/keypath-onboarding-directional-midcross.png`
- Settled light endpoint (unchanged): `/tmp/keypath-onboarding-directional-light.png`

## Iteration 3 — legend alignment and floating chips

The two follow-ups from the directional pass:

- Wide-key legend alignment: the scene model now carries a legend alignment,
  and MacBook conventions are applied from key geometry — `tab`, `caps lock`,
  and left `shift` set leading, row-ending wide keys trailing, everything
  else centered. The Metal legend atlas rasterizes edge-aligned cells flush
  to a fixed padding and the renderer anchors the quad's matching edge at the
  keycap's inner margin; the native overlay applies the same alignment for
  the fallback and accessibility layers.
- Floating chips: the launcher-choice and Rules-handoff affordances no longer
  wear a keycap costume. They render as full capsules with flattened edges, a
  top sheen, a reduced contact shadow, and a deeper, softer cast shadow in
  both render paths, reading as UI chips hovering above the spacebar rather
  than replacing it.

Both changes verified in the re-recorded fallback snapshots (all seven
states) and in an installed Metal-path capture of the settled state, which
confirms the edge-anchored legend quads render correctly on the GPU path.

Additionally, per hands-on feedback that the board's bottom (and after the
first fix, top) edge was cut off: the deck now carries a wider aluminum apron
below the bottom row, and the projection's anisotropic camera no longer zooms
vertically above 1x, so the complete board — top edge through bottom apron,
with both rounded corners — stays in frame in every moment. The horizontal
magnification that matches the reference key width is unchanged; the visible
keyboard is slightly smaller vertically as an accepted tradeoff for never
cropping the object.

## Validation

- `git diff --check`: passed.
- Keyboard-stage scene and legend-atlas tests: 32 runner tests passed.
- Required catalog-sequence regression filter: 3 runner tests passed, including both named XCTest cases.
- Accessibility identifier check: 378 files checked, passed.
- Installed-app dark and light states inspected from a fresh replay: passed.

## Final result

passed
