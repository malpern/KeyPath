# Worktree build cache fragmentation

## Symptom

Fresh feature worktrees spent roughly 90–180 seconds resolving and rebuilding,
then the safe test runner compiled a second graph under `.build-ci`. Repeated
full runs deleted the module cache and sometimes emitted missing `.pcm`
warnings. Quick deploy also warned that it could not recreate `.build/debug`.

## Root cause

The scripts predated the one-thread/one-worktree/one-`.build` rule. Local tests
still isolated themselves in `.build-ci`, reset the module cache by default,
and allowed SwiftPM to resolve unpinned dependency ranges. Switching between
SwiftPM build-system layouts could also leave a generated `debug` symlink aimed
at the other layout.

## Fix

- Commit `Package.resolved` at the dependency revisions already validated on
  master and disable automatic resolution in routine build/test entry points.
- Reuse the worktree's `.build` graph for local app builds and tests.
- Preserve the module cache by default; cache reset remains an explicit
  diagnostic opt-in.
- Remove `.build/debug` only when it is a generated symlink, allowing the pinned
  stable Xcode toolchain to recreate the correct target.
- Canonicalize the quick-deploy project path before deriving cache paths;
  spelling the same directory as both `.build` and `Scripts/../.build` makes
  Clang diagnose duplicate PCM modules and can crash `swift-frontend`.

Each concurrent thread still has independent artifacts because repository
policy gives every thread its own worktree.
