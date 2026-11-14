# KeyPath brand

The product tagline is **Keys that do more.** Use that exact capitalization and
punctuation in onboarding, About, installer, Help branding, and future marketing artwork.

The launch splash is the KeyPath poster,
`Sources/KeyPathApp/Resources/keypath-poster-hor.png` (the keycap, the KeyPath
wordmark and "Tap. Remap. Done.", baked into the image), on the dark gradient in
`KeyPathColors.splashGradientTop`/`Bottom`. It was restored in November 2026 at the
owner's request. The poster's lettering is part of the bitmap, so changing the
splash tagline means a new poster image.

The splash appears on every launch for about 1.2 seconds (`KEYPATH_SPLASH_DELAY_MS`),
then hides and the keyboard overlay appears. It does not appear when KeyPath is
reopened while running, or when macOS starts it at login. On first run it stays up,
with activity dots, until the setup wizard takes over. Activity respects Reduce
Motion and stays off when the same window hosts a menu-action sheet.

