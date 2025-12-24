# Typing Sounds

This directory contains mechanical keyboard sound effects for the typing sounds feature.

## Sound File Naming Convention

Files should be named: `{profile-id}-{down|up}.{mp3|wav}`

Examples:
- `mx-blue-down.mp3` - Cherry MX Blue keydown sound
- `mx-blue-up.mp3` - Cherry MX Blue keyup sound
- `nk-cream-down.wav` - NK Cream keydown sound

## Required Files

For each sound profile in `SoundProfile.all`:
- `mx-blue-down.mp3` / `mx-blue-up.mp3`
- `mx-brown-down.mp3` / `mx-brown-up.mp3`
- `mx-red-down.mp3` / `mx-red-up.mp3`
- `nk-cream-down.mp3` / `nk-cream-up.mp3`
- `bubble-pop-down.mp3` / `bubble-pop-up.mp3`

## Sound Sources

Sound files are sourced from the [Thock](https://github.com/kamillobinski/thock) project,
which is MIT licensed. Many thanks to the Thock contributors for creating these sounds!

## Tips for Good Sounds

- Keep files small (~50KB or less per file)
- Use short samples (50-150ms)
- Keyup sounds should be slightly quieter/shorter than keydown
- Consider adding slight pitch variation in the sound files themselves
