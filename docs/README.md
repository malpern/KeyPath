# KeyPath developer documentation

Developer-facing docs for KeyPath, maintained on `master`. These are **not**
published — the end-user site lives on the `gh-pages` branch (see the
"Documentation" section of the root [`CLAUDE.md`](../CLAUDE.md)).

## Layout

| Directory | Contents |
|-----------|----------|
| [`adr/`](adr/README.md) | Architecture Decision Records |
| [`architecture/`](architecture/) | System architecture, data flow, subsystem deep-dives |
| [`guides/`](guides/README.md) | Feature how-to guides (setup, layouts, tap-hold, app intents, FAQ) |
| [`process/`](process/README.md) | Dev process: PR workflow, release, deployment, linting, contributor guide |
| [`troubleshooting/`](troubleshooting/README.md) | Diagnostics and debugging references |
| [`testing/`](testing/) | Test strategy, coverage, hygiene, and smoke checklists |
| [`research/`](research/README.md) | Background research and analysis notes |
| [`features/`](features/) | Per-feature design and behavior docs |
| [`design/`](design/) | Design specs and UX explorations |
| [`bugs/`](bugs/) | Bug investigations and post-mortems |
| [`analysis/`](analysis/) | Deep-dive investigations and handoffs |
| [`code-review/`](code-review/) | Code-review write-ups |
| [`planning/`](planning/) | Active plans and roadmaps |
| [`archive/`](archive/README.md) | Superseded/historical docs (links may be stale) |

Top-level loose files: this index, [`keypath-cli-skill.md`](keypath-cli-skill.md).

## Conventions

- New docs use **kebab-case** filenames (e.g. `release-process.md`).
- Cross-references between docs are relative links; front-door references from the
  repo root (`README.md`, `CLAUDE.md`, `AGENTS.md`) use repo-relative `docs/...` paths.
