# Repository Guidelines

These guidelines keep contributions fast, predictable, and shippable for the KeyPath Swift package and macOS app.

## Project Structure & Module Organization
- `Sources/KeyPath` – App code (SwiftUI). Subfolders: `Core`, `Managers`, `Services`, `Infrastructure`, `Utilities`, `UI`, `Models`, `InstallationWizard`.
- `Sources/KeyPathCLI` – `main.swift` launcher and simple test harness.
- `Tests/KeyPathTests` – XCTest suites (e.g., `KeyboardCaptureTests.swift`).
- `Scripts/` – build, sign, test, and maintenance scripts.
- `dist/` – created app bundle for local installs.
- Docs: `README.md`, `ARCHITECTURE.md`, `docs/`.

## Build, Test, and Development Commands
- Build (debug): `swift build`
- Run tests (stable on Xcode 26 beta): `./run-tests-workaround.sh`
- Full suite (unit + integration wrappers): `./run-tests.sh`
- Build signed app bundle: `./Scripts/build-and-sign.sh`
- Quick dev build: `./Scripts/build.sh`
- Optional pre-commit hooks: `./Scripts/setup-git-hooks.sh`
- CI preview locally: `.github/workflows/test-ci-locally.sh`

## Coding Style & Naming Conventions
- Language: Swift 6, macOS 14+. Use Swift Concurrency; prefer `@MainActor` for UI-bound code.
- Formatting/Lint: SwiftFormat (optional) and SwiftLint configured via `.swiftlint.yml`.
- Indentation: 4 spaces; 120–200 char soft guidance (see lint config).
- Naming: Types `UpperCamelCase`, methods/vars `lowerCamelCase`, constants `lowerCamelCase`.
- Avoid `print()`; use a logging utility. Avoid force unwraps in `Managers/`.

## Testing Guidelines
- Framework: XCTest. Place tests in `Tests/KeyPathTests`, name files `*Tests.swift` and test methods `test…`.
- Run locally with `./run-tests.sh` (or `./run-tests-workaround.sh` on beta toolchains).
- Prefer deterministic tests; mock services; mark UI tests `@MainActor`.
- Aim to add tests alongside new or changed code; keep integration scripts under `Scripts/test-*.sh` if needed.
- Coverage: no hard gate; prioritize `Managers/`, installer paths, and UDP client behavior.

## Commit & Pull Request Guidelines
- Commits: Imperative mood (e.g., “Fix permission detection”). Optional prefixes like `fix:`, `feat:`, `docs:` allowed. Include a short body explaining the why when non-trivial.
- PRs: Link issues, describe scope and approach, include repro/validation steps. Attach screenshots for UI changes. Ensure `./run-tests.sh` passes before requesting review.

## Security & Configuration Tips
- App requires Input Monitoring and Accessibility; do not bypass macOS TCC checks.
- Keep entitlements in `KeyPath.entitlements`; avoid hardcoded privileged paths. Use `Scripts/` helpers for Kanata/daemon tasks.

## Agent-Specific Instructions
- Keep diffs minimal and focused; preserve directory layout and script entry points.
- Update docs when behavior or commands change; prefer adding tests over ad hoc fixes.
