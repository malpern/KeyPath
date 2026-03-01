# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project follows Semantic
Versioning once public release tags are established.

## [Unreleased]

### Added

- Release-governance docs: `SECURITY.md`, `CODE_OF_CONDUCT.md`, and this
  changelog.
- CI/release-readiness tracking issues labeled as `release-blocker` in Linear.
- Mapper/overlay support for optional per-key shifted output customization:
  `Shift + key` can now send a separate output from tap/default output for
  global keystroke mappings.

### Changed

- Documentation and CI policy are being aligned for open source release quality
gates.
- CI now enforces coverage non-regression for the narrow baseline lane:
  `KeyPathErrorTests` + `PermissionOracleTests` with an initial floor of
  `0.29%` TOTAL line coverage.
- Shifted-output editing is intentionally constrained to global keystroke
  mappings and is disabled for app-specific mappings, system actions, URLs, and
  advanced hold/combo/tap-dance behaviors.

## [0.0.0-internal]

### Notes

- Pre-public-release baseline. Historical internal changes prior to OSS launch
  are tracked in git history and project documentation.
