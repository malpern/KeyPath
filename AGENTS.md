# AGENTS.md

These instructions apply to all Codex sessions in this repository.

## Web Search Tooling
- Always use `web_search_request` for any web lookups.
- Never call the deprecated `tools.web_search` tool. Treat it as unavailable.
- Do not pass the CLI flag `--search`. Rely on the feature flag or config instead.

Rationale: older CLI/tooling may still expose `tools.web_search`, which prints a deprecation warning. Enforcing `web_search_request` avoids the warning and keeps behavior consistent.

## General
- Keep diffs minimal and focused. Preserve directory layout and script entry points.
- Update docs/tests when behavior or commands change.
