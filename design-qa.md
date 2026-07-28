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

## Validation

- `git diff --check`: passed.
- Keyboard-stage scene and legend-atlas tests: 32 runner tests passed.
- Required catalog-sequence regression filter: 3 runner tests passed, including both named XCTest cases.
- Accessibility identifier check: 378 files checked, passed.
- Installed-app dark and light states inspected from a fresh replay: passed.

## Final result

passed
