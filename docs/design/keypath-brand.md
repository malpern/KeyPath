# KeyPath brand

The product tagline is **Keys that do more.** Use that exact capitalization and
punctuation in onboarding, About, installer, Help branding, and future marketing artwork.

The launch splash is the KeyPath poster,
`Sources/KeyPathApp/Resources/keypath-poster-hor.png` (the keycap, the KeyPath
wordmark and "Tap. Remap. Done.", baked into the image), on the dark gradient in
`KeyPathColors.splashGradientTop`/`Bottom`. It was restored in November 2026 at the
owner's request. The poster's lettering is part of the bitmap, so changing the
splash tagline means a new poster image.

The splash appears on every launch and stays until the keyboard overlay is up,
for at least 1.2 seconds (`KEYPATH_SPLASH_DELAY_MS`); the overlay appears first, then
the splash hides. If starting the engine takes longer, activity dots appear under
the poster. If startup stalls, the poster goes after 15 seconds and the overlay
follows when ready. It does not appear when KeyPath is reopened while running, or
when macOS starts it at login. When setup is not finished, the same window shows
activity dots and then the setup wizard. The splash window has the poster's
shape and the poster fills it; the activity line and the version sit on the poster's
dark lower band, not below it. Activity respects Reduce
Motion and stays off when the same window hosts a menu-action sheet.

