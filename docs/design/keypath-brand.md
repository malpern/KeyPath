# KeyPath brand

The product tagline is **Keys that do more.** Use that exact capitalization and
punctuation in splash, onboarding, About, installer, Help branding, and future marketing artwork.
The former “Tap. Remap. Done.” tagline is retired. Do not bring back the old
poster resources as fallbacks: their lettering is baked into the images.

The splash and installer pair a warm ivory serif KeyPath wordmark with a smaller,
regular sans-serif tagline in warm gray. Use near-black blue charcoal and the
sculptural amber keycap; keep glow localized and typography flat and readable.
Render text natively instead of baking it into a bitmap. The splash emblem is
`Sources/KeyPathApp/Resources/keypath-splash-emblem.png`.

The splash shows subtle activity only during the existing startup handoff. It
must retire activity at the handoff, respect Reduce Motion, and remain static
when the same window hosts a menu-action sheet. Do not add a minimum display
time or delay a ready application for an animation.

The isolated emblem was produced with built-in Image Gen from the approved
2026-10-18 splash concept. Prompt: transparent cutout of the recognizable orange
keycap with raised lid and warm ivory center; preserve proportions and orientation;
no text, chrome, broad haze, backdrop, or external shadow. The source generation
remains in the local generated-images library; the project owns the bundled copy.
