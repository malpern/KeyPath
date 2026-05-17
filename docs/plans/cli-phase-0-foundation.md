# Phase 0: CLI Foundation — Noun-Verb + Progressive Disclosure

**Issue:** #347 (CLI parity)  
**Blocker:** #346 (action model unification) — DONE  
**Status:** Phase 0 design locked, ready for implementation

## Context

The existing `keypath-cli` has 12 flat commands covering ~60% of GUI functionality. Phase 0 restructures these into a noun-verb architecture with proper output infrastructure — the foundation all later phases build on.

**Design philosophy** (informed by Notion CLI study): agent-first, human-compatible. Progressive disclosure via self-documenting subcommands. Structured errors with What+Why+Hint. TTY detection auto-formats output for the consumer.

## Current State → Target State

### Current (12 flat commands)
```
keypath-cli status | remap | rules {list,enable,disable,show} | layer {list,switch}
           | apply | config {show,path,check} | tcp {status,layers,reload,hrm-stats}
           | install | repair | uninstall | inspect | completions
```

### Target (noun-verb plumbing + porcelain shortcuts)
```
keypath rule list | add | remove | show        ← was: remap, rules show
keypath collection list | enable | disable | show  ← was: rules {list,enable,disable,show}
keypath layer list | switch                    ← same, just regrouped
keypath service status | reload                ← was: status, tcp reload
keypath config show | path | check | apply     ← was: config + apply merged
keypath system install | repair | uninstall | inspect  ← was: top-level install/repair/etc
keypath completions {zsh,bash,fish}            ← unchanged
keypath help schemas                           ← new (progressive disclosure for agents)

# Porcelain shortcuts (sugar over plumbing)
keypath status   → keypath service status      ← existing shortcut kept
keypath remap    → keypath rule add            ← existing shortcut kept
```

## Implementation Plan

### 1. Output Infrastructure (`Sources/KeyPathCLI/Utilities/Output.swift`)

New file — the foundation for all output.

```swift
/// TTY detection + output formatting
/// - When stdout is a TTY: human-friendly tables, status icons, hints
/// - When piped (not a TTY): clean JSON (auto-detected, no flag needed)
/// - --json flag: force JSON even in TTY
/// - --no-json flag: force human even when piped
/// - NO_COLOR env var: strip ANSI (per https://no-color.org)
struct OutputContext {
    let isInteractive: Bool  // isatty(STDOUT_FILENO)
    let forceJSON: Bool      // --json flag
    let forceHuman: Bool     // --no-json flag
    let noColor: Bool        // NO_COLOR env var

    var shouldOutputJSON: Bool { forceJSON || (!forceHuman && !isInteractive) }
}
```

Key behaviors:
- `isatty(STDOUT_FILENO)` detects pipe vs terminal
- JSON output goes to stdout; human decoration to stderr (keeps stdout machine-parseable)
- Progress messages ("Starting installation...") only emit when interactive

### 2. Structured Error Envelope (`Sources/KeyPathCLI/Utilities/CLIError.swift`)

New file — every error follows the What+Why+Hint pattern (Notion's structured error design).

```swift
struct CLIError: Error, Codable {
    let code: CLIExitCode
    let message: String      // What happened
    let hint: String?        // What to do about it (agent can self-correct)
    let details: [String]?   // Additional context
    let docsUrl: String?     // Progressive disclosure: point to more info
}

enum CLIExitCode: Int32, Codable {
    case success = 0
    case usage = 2           // Bad arguments / unknown command
    case validation = 3      // Rule/config validation failed
    case conflict = 4        // Rule conflict
    case notFound = 5        // Collection/rule/layer not found
    case serviceUnreachable = 6  // Kanata TCP not responding
    case permissionBlocked = 7   // Missing macOS permissions
    case kanataInvalid = 8       // kanata --check failed
}
```

JSON error output on stderr:
```json
{"code": 5, "message": "Collection not found", "hint": "Run 'keypath collection list' to see available collections", "details": ["query: 'vim'"], "docsUrl": null}
```

### 3. Global Options Protocol (`Sources/KeyPathCLI/Utilities/GlobalOptions.swift`)

New file — shared flags inherited by all commands via `ParsableArguments`.

```swift
struct GlobalOptions: ParsableArguments {
    @Flag(help: "Force JSON output")
    var json: Bool = false

    @Flag(help: "Force human-readable output")
    var noJson: Bool = false

    @Flag(help: "Preview changes without applying")
    var dryRun: Bool = false

    @Option(help: "Conflict resolution: fail|replace|skip")
    var onConflict: ConflictStrategy = .fail
}
```

### 4. Noun-Verb Command Restructure

#### File mapping (old → new):

| Old File | New File(s) | Notes |
|----------|-------------|-------|
| `RemapCommand.swift` | `Commands/Rule/RuleCommand.swift` + subcommands | Split into group |
| `RulesCommand.swift` | `Commands/Collection/CollectionCommand.swift` + subcommands | Rename rules→collection |
| `LayerCommand.swift` | `Commands/Layer/LayerCommand.swift` + subcommands | Same structure, add global opts |
| `StatusCommand.swift` | `Commands/Service/ServiceCommand.swift` + subcommands | Status moves under service |
| `ApplyCommand.swift` | `Commands/Config/ConfigApplyCommand.swift` | Merge into config group |
| `ConfigCommand.swift` | `Commands/Config/ConfigCommand.swift` + subcommands | Add apply, keep show/path/check |
| `TCPCommand.swift` | Absorbed into `Service/` commands | reload→service reload |
| `InstallCommand.swift` | `Commands/System/SystemCommand.swift` + subcommands | Group under system |
| `CompletionsCommand.swift` | `Commands/CompletionsCommand.swift` | Unchanged |

#### New directory structure:
```
Sources/KeyPathCLI/
├── KeyPathTool.swift           (updated root command)
├── Commands/
│   ├── Rule/
│   │   ├── RuleCommand.swift       (group: rule {list,add,remove,show})
│   │   ├── RuleAddCommand.swift
│   │   ├── RuleRemoveCommand.swift
│   │   ├── RuleListCommand.swift
│   │   └── RuleShowCommand.swift
│   ├── Collection/
│   │   ├── CollectionCommand.swift
│   │   ├── CollectionListCommand.swift
│   │   ├── CollectionEnableCommand.swift
│   │   ├── CollectionDisableCommand.swift
│   │   └── CollectionShowCommand.swift
│   ├── Layer/
│   │   ├── LayerCommand.swift
│   │   ├── LayerListCommand.swift
│   │   └── LayerSwitchCommand.swift
│   ├── Service/
│   │   ├── ServiceCommand.swift
│   │   ├── ServiceStatusCommand.swift
│   │   └── ServiceReloadCommand.swift
│   ├── Config/
│   │   ├── ConfigCommand.swift
│   │   ├── ConfigShowCommand.swift
│   │   ├── ConfigPathCommand.swift
│   │   ├── ConfigCheckCommand.swift
│   │   └── ConfigApplyCommand.swift
│   ├── System/
│   │   ├── SystemCommand.swift
│   │   ├── SystemInstallCommand.swift
│   │   ├── SystemRepairCommand.swift
│   │   ├── SystemUninstallCommand.swift
│   │   └── SystemInspectCommand.swift
│   ├── Help/
│   │   ├── HelpCommand.swift
│   │   └── HelpSchemasCommand.swift
│   ├── Porcelain/
│   │   ├── StatusShortcut.swift    (keypath status → service status)
│   │   └── RemapShortcut.swift     (keypath remap → rule add)
│   └── CompletionsCommand.swift
└── Utilities/
    ├── Output.swift            (NEW: TTY detection, OutputContext)
    ├── CLIError.swift          (NEW: structured errors, exit codes)
    ├── GlobalOptions.swift     (NEW: --json, --dry-run, --on-conflict)
    ├── ApplyHelper.swift       (updated for structured errors)
    └── Timeout.swift           (unchanged)
```

### 5. Progressive Disclosure: `keypath help schemas`

New scaffolding command that agents discover incrementally:
```
keypath help schemas           → list available schema names + one-line descriptions
keypath help schemas rule      → show rule add/remove JSON schema
keypath help schemas action    → show all Action type variants
keypath help schemas collection → show collection CRUD schema
```

This is Notion's Level 3 — self-documenting commands. An agent doesn't need the full API surface upfront; it calls `keypath help schemas <noun>` to learn just the part it needs.

### 6. Porcelain Aliases (backward compat)

Keep `keypath status` and `keypath remap` as top-level porcelain shortcuts that delegate to plumbing. These are thin wrappers — no logic, just forwarding. Porcelain is sugar over plumbing, never the other way around.

### 7. Root Command Update

```swift
@main
struct KeyPathCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "keypath",  // ← rename from "keypath-cli"
        abstract: "KeyPath keyboard remapping — configure, query, control",
        version: CLIVersion.current,
        subcommands: [
            // Plumbing (noun-verb)
            Rule.self, Collection.self, Layer.self,
            Service.self, Config.self, System.self,
            Help.self, Completions.self,
            // Porcelain shortcuts
            StatusShortcut.self, RemapShortcut.self,
        ]
    )
}
```

### 8. Tests

The CLI is an agent contract — if a JSON field changes or an exit code shifts, an agent's workflow breaks silently. Tests must protect the output shape as rigorously as the logic.

#### Existing (unchanged)
- `CLIFacadeTests.swift` — 11 tests covering collection resolution and key validation

#### New test files

**`Tests/KeyPathTests/CLI/OutputTests.swift`** — Output infrastructure
- `testShouldOutputJSON_whenForceJSON` — `--json` flag forces JSON even in TTY
- `testShouldOutputJSON_whenNotInteractive` — piped output auto-selects JSON
- `testShouldOutputHuman_whenInteractiveNoFlags` — TTY defaults to human
- `testShouldOutputHuman_whenForceNoJSON` — `--no-json` overrides pipe detection
- `testNoColorRespectsEnvironment` — `NO_COLOR` env strips ANSI
- `testJSONOutputIsValidJSON` — every Codable CLI type round-trips through encoder/decoder

**`Tests/KeyPathTests/CLI/CLIErrorTests.swift`** — Structured error contract
- `testErrorEncodesAsJSON` — CLIError → JSON has all expected fields (code, message, hint, details, docsUrl)
- `testAllExitCodesHaveUniqueValues` — no two CLIExitCode cases share a raw value
- `testExitCodeRawValues` — pin exact numeric values (0, 2, 3, 4, 5, 6, 7, 8) — changing these breaks agents
- `testErrorHintIsNonEmpty` — every CLIError factory method provides a hint (agents need actionable guidance)
- `testNotFoundErrorSuggestsListCommand` — hint for `.notFound` includes the relevant `list` subcommand

**`Tests/KeyPathTests/CLI/OutputContractTests.swift`** — JSON shape stability (snapshot-style)
- `testStatusJSONShape` — CLIStatusResult encodes with every expected key; new keys are additive-only
- `testRuleCollectionJSONShape` — CLIRuleCollection JSON has id, name, isEnabled, mappingCount, summary
- `testApplyResultJSONShape` — CLIApplyResult JSON has collectionsCount, enabledCount, customRulesCount, reloadSuccess
- `testInstallerReportJSONShape` — CLIInstallerReport JSON has success, failureReason, steps[], fastRepair
- `testErrorJSONShape` — CLIError JSON has code, message, hint, details, docsUrl
- `testJSONKeysAreStable` — encode each CLI type, decode into `[String: Any]`, assert key sets match expected

**`Tests/KeyPathTests/CLI/CommandStructureTests.swift`** — Command tree integrity
- `testRootHasExpectedSubcommands` — KeyPathCLI.configuration.subcommands contains Rule, Collection, Layer, Service, Config, System, Help, Completions + porcelain
- `testRuleHasExpectedVerbs` — Rule subcommands: list, add, remove, show
- `testCollectionHasExpectedVerbs` — Collection subcommands: list, enable, disable, show
- `testServiceHasExpectedVerbs` — Service subcommands: status, reload
- `testConfigHasExpectedVerbs` — Config subcommands: show, path, check, apply
- `testSystemHasExpectedVerbs` — System subcommands: install, repair, uninstall, inspect
- `testPorcelainStatusDelegatesToServiceStatus` — StatusShortcut produces same output context
- `testPorcelainRemapDelegatesToRuleAdd` — RemapShortcut produces same output context
- `testCommandNameIsKeypath` — root commandName is "keypath" not "keypath-cli"

### 9. CLI–GUI Parity Guard (Compile-Time)

**Problem:** As the GUI adds new `KeyAction` variants or `MappingBehavior` cases, the CLI silently falls behind unless someone remembers to update it.

**Solution:** Exhaustive `switch` statements in the CLI's schema description layer. Swift's compiler enforces this — adding a new `KeyAction.foo` case makes the CLI fail to compile until it's handled.

#### Implementation

**`Sources/KeyPathAppKit/CLI/CLIActionDescription.swift`** — new file in the facade layer:

```swift
/// Maps every KeyAction case to a CLI schema description.
/// Exhaustive switch ensures the CLI won't compile if a new action is added
/// without CLI support.
extension KeyAction {
    /// Schema name used in `keypath help schemas action`
    public var cliSchemaName: String {
        switch self {
        case .keystroke: "key"
        case .hyper: "hyper"
        case .meh: "meh"
        case .launchApp: "launch-app"
        case .openURL: "open-url"
        case .openFolder: "open-folder"
        case .runScript: "run-script"
        case .systemAction: "system-action"
        case .notify: "notify"
        case .windowAction: "window"
        case .fakeKey: "fake-key"
        case .activateLayer: "activate-layer"
        case .rawKanata: "raw-kanata"
        }
    }
}

/// Maps every MappingBehavior case to a CLI schema description.
extension MappingBehavior {
    public var cliSchemaName: String {
        switch self {
        case .dualRole: "tap-hold"
        case .tapOrTapDance: "tap-dance"
        case .macro: "macro"
        case .chord: "chord"
        }
    }
}
```

**Why this works:**
- Swift exhaustive `switch` is a **compile-time** guarantee — no test to forget to run
- Lives in `KeyPathAppKit` (not the CLI binary) so it's compiled with every `swift build`
- The `help schemas action` command uses `cliSchemaName` to generate its output, so the schema docs stay in sync automatically
- Zero runtime cost — these are just string mappings

#### Parity test (belt + suspenders)

**`Tests/KeyPathTests/CLI/CLIParityTests.swift`**:
- `testAllKeyActionCasesHaveCLISchemaName` — iterate `KeyAction.allCases` (if CaseIterable) or use Mirror, assert `cliSchemaName` is non-empty for each
- `testAllMappingBehaviorCasesHaveCLISchemaName` — same for MappingBehavior
- `testSchemaNamesDontCollide` — no two variants share a schema name
- `testHelpSchemasListsAllActions` — the `help schemas action` output includes every `cliSchemaName`

The compile-time switch is the primary guard. The tests are a secondary net that catches naming collisions and documentation gaps.

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| `keypath` not `keypath-cli` | Simpler, matches app name, what users type |
| Auto-JSON when piped | Notion pattern: agents get JSON by default without asking |
| Errors on stderr, data on stdout | Clean separation for piping and scripting |
| Semantic exit codes | Agents branch on code without parsing text |
| `--dry-run` everywhere | Agents validate before mutating (idempotent verification) |
| `help schemas` for progressive disclosure | Agent discovers API shape incrementally, not 100-tool dump |
| Porcelain delegates to plumbing | One implementation, two interfaces. Never invert this. |

## Files Modified

- `Sources/KeyPathCLI/KeyPathTool.swift` — new command tree
- `Package.swift` — product name `keypath-cli` → `keypath`
- `Sources/KeyPathCLI/Utilities/ApplyHelper.swift` — structured errors

## Files Deleted (replaced by new structure)

- `Sources/KeyPathCLI/Commands/RemapCommand.swift`
- `Sources/KeyPathCLI/Commands/RulesCommand.swift`
- `Sources/KeyPathCLI/Commands/StatusCommand.swift`
- `Sources/KeyPathCLI/Commands/ApplyCommand.swift`
- `Sources/KeyPathCLI/Commands/ConfigCommand.swift`
- `Sources/KeyPathCLI/Commands/TCPCommand.swift`
- `Sources/KeyPathCLI/Commands/InstallCommand.swift`
- `Sources/KeyPathCLI/Commands/LayerCommand.swift`

## Files Created

All files in the new directory structure (Section 4), plus:
- `Sources/KeyPathCLI/Utilities/Output.swift`
- `Sources/KeyPathCLI/Utilities/CLIError.swift`
- `Sources/KeyPathCLI/Utilities/GlobalOptions.swift`
- `Sources/KeyPathAppKit/CLI/CLIActionDescription.swift` (parity guard)
- `Tests/KeyPathTests/CLI/OutputTests.swift`
- `Tests/KeyPathTests/CLI/CLIErrorTests.swift`
- `Tests/KeyPathTests/CLI/OutputContractTests.swift`
- `Tests/KeyPathTests/CLI/CommandStructureTests.swift`
- `Tests/KeyPathTests/CLI/CLIParityTests.swift`

## Verification

1. `swift build` — compiles cleanly (parity guard included — adding a new KeyAction case without CLI support will fail here)
2. `swift test --filter CLI` — all CLI tests pass (~30+ tests across 6 files)
3. `.build/debug/keypath --help` — shows noun-verb structure
4. `.build/debug/keypath rule --help` — progressive disclosure (shows subcommands)
5. `.build/debug/keypath service status --json` — structured JSON output
6. `.build/debug/keypath service status` — human-friendly output (when TTY)
7. `.build/debug/keypath service status | cat` — auto-JSON when piped
8. `.build/debug/keypath collection enable nonexistent` — structured error with hint, exit code 5
9. `.build/debug/keypath help schemas` — lists available schemas
10. **Parity guard smoke test:** temporarily add a fake `KeyAction` case → verify `swift build` fails in `CLIActionDescription.swift`
