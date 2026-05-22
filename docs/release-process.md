# Release Process

To publish a new release, run:

```bash
./Scripts/release.sh 1.0.0-beta4    # Specify the new version
./Scripts/release.sh --dry-run 1.0.0-beta4  # Preview without doing anything
```

**The script automates:**
1. Version bump in Info.plist (CFBundleVersion + CFBundleShortVersionString)
2. Full build, code sign, **notarize**, and Sparkle EdDSA signing
3. Styled DMG creation (branded background, drag-to-Applications)
4. Git tag creation
5. GitHub Release with zip + DMG attached
6. Appcast.xml update (Sparkle auto-update feed)
7. gh-pages download link update (marketing site always points to latest DMG)
8. Homebrew cask update (`malpern/tap/keypath` — version + SHA256)

**⚠️ Releases MUST be notarized.** Never use `SKIP_NOTARIZE=1` or `--skip-notarize` for release builds. Unnotarized apps trigger macOS Gatekeeper warnings that erode user trust. `SKIP_NOTARIZE` is only for local dev iteration (`dd`/`df` shortcuts).

**After the script finishes, you must:**
1. Write release notes on the GitHub Release page
2. `git push` to push the appcast commit on master

**Sparkle auto-update:** Existing users get notified within 24 hours. The appcast is served from `raw.githubusercontent.com/malpern/KeyPath/master/appcast.xml`. All releases currently omit `sparkle:channel` so all users see them (no stable/beta split yet).

**Marketing site:** The download button on keypath-app.com links to the DMG. The release script updates this automatically via a gh-pages worktree commit. Never hardcode a version-specific download URL in index.md manually.

**Homebrew cask:** Users can install via `brew install --cask malpern/tap/keypath`. The cask lives in `github.com/malpern/homebrew-tap/Casks/keypath.rb`. The release script updates the version and SHA256 automatically.
