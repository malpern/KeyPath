---
layout: default
title: Context Integration Architecture
description: How KeyPath receives context from external tools for dynamic contextual help
---

# Context Integration Architecture

This document outlines how KeyPath can receive context from external tools (tmux, shell, vim, etc.) to provide dynamic contextual keyboard help.

## Problem Statement

KeyPath currently knows the **frontmost application** via NSWorkspace, enabling app-specific keymaps. However, many power users work primarily in terminal emulators, where the active app is always "Terminal" or "iTerm2"—even though the actual tool (tmux, vim, shell) changes constantly.

**Example:** A user presses `Ctrl+B` in tmux to enter command mode. KeyPath should show tmux command hints, but without context, it only knows "iTerm2 is active."

## Goal

Provide dynamic, contextual keyboard help based on the **actual tool state**, not just the frontmost app.

## Architecture Overview

```
┌────────────────────────────────────────────────────────────────────┐
│                           External Tools                            │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐           │
│  │  tmux    │  │  vim     │  │  shell   │  │  other   │           │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘           │
│       │             │             │             │                   │
│       └─────────────┴─────────────┴─────────────┘                   │
│                           │                                         │
│                           ▼                                         │
│               ┌───────────────────────┐                            │
│               │   Context Message     │                            │
│               │   (JSON over TCP)     │                            │
│               └───────────┬───────────┘                            │
└───────────────────────────┼────────────────────────────────────────┘
                            │
                            ▼
┌───────────────────────────────────────────────────────────────────┐
│  KeyPath                                                           │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │  TCP Server (port 37001)                                     │  │
│  │  - Existing Kanata protocol                                  │  │
│  │  - Extended with context-update messages                     │  │
│  └─────────────────────────────┬───────────────────────────────┘  │
│                                │                                   │
│                                ▼                                   │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │  Context Store                                               │  │
│  │  - Per-source state (tmux, vim, shell)                      │  │
│  │  - Merged with app-level context                            │  │
│  └─────────────────────────────┬───────────────────────────────┘  │
│                                │                                   │
│                                ▼                                   │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │  Visual Help System                                          │  │
│  │  - Overlay hints                                             │  │
│  │  - Contextual keycap labels                                  │  │
│  └─────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────┘
```

## Integration Layers

Context integration operates at multiple layers, each with different trade-offs.

### Layer 1: App-Level Context (Existing)

**What it does:** Detects the frontmost application via NSWorkspace.

**Already implemented in KeyPath.** This layer provides app-specific keymaps (e.g., Safari shortcuts when Safari is active).

**Limitation:** Cannot distinguish between tools running inside a terminal.

### Layer 2: Keystroke Pattern Detection

**What it does:** Passively observes key sequences to infer tool state.

**Example:** When the user types `Ctrl+B`, KeyPath can infer "tmux command mode may be active" and display tmux command hints for 2-3 seconds.

**Implementation:**
- Kanata already sees all keystrokes
- KeyPath can detect prefix patterns (Ctrl+B for tmux, Escape for vim normal mode)
- No external tool configuration required

**Pros:**
- Zero configuration for users
- Works immediately with any terminal
- No dependencies on external tools

**Cons:**
- Best-guess only—can't know if tmux is actually running
- Ambiguous states (Ctrl+B could be tmux or a different binding)
- Limited context (can't know tmux session name, window, etc.)

**When to use:** Quick wins, fallback when no explicit integration exists.

### Layer 3: Shell Integration

**What it does:** Hooks into zsh/bash `precmd`/`preexec` to send context updates.

**Context available:**
- Current working directory
- Last command executed
- Exit status of last command
- Git branch (if in a git repo)
- Active virtualenv/conda environment

**Example shell integration (zsh):**

```zsh
# ~/.zshrc
keypath_context_update() {
  # Send context to KeyPath via nc (netcat)
  local git_branch=""
  if git rev-parse --git-dir &>/dev/null; then
    git_branch=$(git branch --show-current 2>/dev/null)
  fi

  local payload=$(cat <<EOF
{"ContextUpdate": {
  "source": "shell",
  "state": {
    "cwd": "$PWD",
    "last_command": "$1",
    "git_branch": "$git_branch",
    "shell": "zsh"
  }
}}
EOF
)
  echo "$payload" | nc -q0 127.0.0.1 37001 &>/dev/null &
}

# Hook into zsh
precmd() { keypath_context_update "" }
preexec() { keypath_context_update "$1" }
```

**Pros:**
- Rich shell context (cwd, git, commands)
- Reliable—shell always knows its state
- User configurable

**Cons:**
- Requires shell configuration
- Only covers shell—not vim, tmux, etc.
- Context updates on command completion (slight lag)

**When to use:** Broad shell coverage, git-aware hints.

### Layer 4: Explicit Tool Notifications (TCP)

**What it does:** Tools send their state directly to KeyPath via TCP.

This is the **recommended approach** for deep tool integration. Tools like tmux have built-in hook systems that can send context on state changes.

**Protocol:** KeyPath's existing TCP server (port 37001) is extended to accept context messages:

```json
{
  "ContextUpdate": {
    "source": "tmux",
    "state": {
      "mode": "copy",
      "session": "dev",
      "window": "code",
      "pane_count": 3
    }
  }
}
```

**Response:** KeyPath responds with acknowledgment:

```json
{"status": "Ok"}
```

**Pros:**
- Authoritative—tool knows its exact state
- Rich context (modes, sessions, selections)
- Immediate updates (no polling)

**Cons:**
- Requires tool configuration
- Each tool needs integration setup

**When to use:** Primary integration for power-user tools (tmux, vim/neovim).

## TCP Protocol Extension

### Message Format

Context updates use the existing TCP message format with a new message type:

```json
{
  "ContextUpdate": {
    "source": "string",     // Tool identifier: "tmux", "vim", "shell"
    "state": {              // Tool-specific state (flexible schema)
      "mode": "string",     // Current mode/state
      ...                   // Additional fields per tool
    },
    "timestamp": "ISO8601", // Optional, for ordering
    "ttl_ms": 5000          // Optional, context expiry in ms
  }
}
```

### Supported Sources

| Source   | Expected State Fields                              |
|----------|---------------------------------------------------|
| `tmux`   | `mode`, `session`, `window`, `pane_count`        |
| `vim`    | `mode`, `filetype`, `buffer`, `is_modified`      |
| `neovim` | Same as vim, plus `lsp_status`                   |
| `shell`  | `cwd`, `last_command`, `git_branch`, `shell`     |
| `custom` | Any user-defined fields                           |

### Context Storage & Merging

KeyPath maintains a context store with the most recent state per source:

```swift
struct ToolContext {
    let source: String
    let state: [String: Any]
    let receivedAt: Date
    let ttl: TimeInterval?
}

class ContextStore {
    private var contexts: [String: ToolContext] = [:]

    func update(_ context: ToolContext) {
        contexts[context.source] = context
    }

    func currentContext() -> MergedContext {
        // Merge all non-expired contexts
        // Priority: tool-specific > app-level
    }
}
```

### TTL & Expiration

Context entries expire after their TTL (default: 10 seconds). This handles:
- Tool exits without sending "clear" message
- Stale state after long pauses
- Reconnection scenarios

## Example Integrations

### tmux Integration

tmux has a powerful hook system. Add this to `~/.tmux.conf`:

```bash
# Send context updates to KeyPath on mode and pane changes
set-hook -g pane-mode-changed 'run-shell "echo '\''{\"ContextUpdate\":{\"source\":\"tmux\",\"state\":{\"mode\":\"#{pane_mode}\",\"session\":\"#{session_name}\",\"window\":\"#{window_name}\"}}}'\'' | nc -q0 127.0.0.1 37001 2>/dev/null &"'

set-hook -g client-session-changed 'run-shell "echo '\''{\"ContextUpdate\":{\"source\":\"tmux\",\"state\":{\"mode\":\"normal\",\"session\":\"#{session_name}\",\"window\":\"#{window_name}\"}}}'\'' | nc -q0 127.0.0.1 37001 2>/dev/null &"'

set-hook -g window-linked 'run-shell "echo '\''{\"ContextUpdate\":{\"source\":\"tmux\",\"state\":{\"mode\":\"normal\",\"session\":\"#{session_name}\",\"window\":\"#{window_name}\"}}}'\'' | nc -q0 127.0.0.1 37001 2>/dev/null &"'
```

**Simpler alternative using a helper script:**

Create `~/.local/bin/keypath-tmux-context`:

```bash
#!/bin/bash
# Send tmux context to KeyPath
MODE="${1:-normal}"
SESSION=$(tmux display-message -p '#{session_name}' 2>/dev/null || echo "")
WINDOW=$(tmux display-message -p '#{window_name}' 2>/dev/null || echo "")

cat <<EOF | nc -q0 127.0.0.1 37001 2>/dev/null &
{"ContextUpdate":{"source":"tmux","state":{"mode":"$MODE","session":"$SESSION","window":"$WINDOW"}}}
EOF
```

Then in `~/.tmux.conf`:

```bash
set-hook -g pane-mode-changed 'run-shell "~/.local/bin/keypath-tmux-context #{pane_mode}"'
set-hook -g client-session-changed 'run-shell "~/.local/bin/keypath-tmux-context normal"'
```

### Vim/Neovim Integration

Add to `~/.config/nvim/init.lua` (Neovim):

```lua
-- Send context updates to KeyPath
local function send_keypath_context()
  local mode_map = {
    n = "normal", i = "insert", v = "visual", V = "visual-line",
    ["\22"] = "visual-block", c = "command", R = "replace", t = "terminal"
  }

  local mode = mode_map[vim.fn.mode()] or vim.fn.mode()
  local filetype = vim.bo.filetype or ""
  local bufname = vim.fn.bufname() or ""

  local payload = string.format(
    '{"ContextUpdate":{"source":"neovim","state":{"mode":"%s","filetype":"%s","buffer":"%s"}}}',
    mode, filetype, bufname:gsub('"', '\\"')
  )

  -- Non-blocking send via jobstart
  vim.fn.jobstart({'nc', '-q0', '127.0.0.1', '37001'}, {
    stdin = 'pipe',
    on_stdin = function(_, _) end,
  })
  vim.fn.chansend(vim.fn.jobstart({'nc', '-q0', '127.0.0.1', '37001'}), payload)
end

-- Hook into mode changes
vim.api.nvim_create_autocmd({"ModeChanged", "BufEnter"}, {
  callback = send_keypath_context
})
```

For Vim (vimscript), add to `~/.vimrc`:

```vim
" Send context to KeyPath on mode change
function! SendKeypathContext()
  let l:mode = mode()
  let l:mode_map = {'n': 'normal', 'i': 'insert', 'v': 'visual', 'V': 'visual-line', 'c': 'command'}
  let l:mode_name = get(l:mode_map, l:mode, l:mode)
  let l:payload = '{"ContextUpdate":{"source":"vim","state":{"mode":"' . l:mode_name . '","filetype":"' . &filetype . '"}}}'
  silent! call system('echo ' . shellescape(l:payload) . ' | nc -q0 127.0.0.1 37001 &')
endfunction

autocmd ModeChanged * call SendKeypathContext()
autocmd BufEnter * call SendKeypathContext()
```

### Shell Integration (zsh)

Add to `~/.zshrc`:

```zsh
# KeyPath context integration
_keypath_send_context() {
  local git_branch=""
  if git rev-parse --git-dir &>/dev/null 2>&1; then
    git_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "detached")
  fi

  local venv=""
  [[ -n "$VIRTUAL_ENV" ]] && venv=$(basename "$VIRTUAL_ENV")

  local payload="{\"ContextUpdate\":{\"source\":\"shell\",\"state\":{\"cwd\":\"$PWD\",\"git_branch\":\"$git_branch\",\"venv\":\"$venv\"}}}"

  echo "$payload" | nc -q0 127.0.0.1 37001 2>/dev/null &!
}

# Send on directory change and prompt
add-zsh-hook chpwd _keypath_send_context
add-zsh-hook precmd _keypath_send_context
```

For bash, add to `~/.bashrc`:

```bash
# KeyPath context integration
_keypath_send_context() {
  local git_branch=""
  if git rev-parse --git-dir &>/dev/null 2>&1; then
    git_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "detached")
  fi

  local payload="{\"ContextUpdate\":{\"source\":\"shell\",\"state\":{\"cwd\":\"$PWD\",\"git_branch\":\"$git_branch\"}}}"

  echo "$payload" | nc -q0 127.0.0.1 37001 2>/dev/null &
}

PROMPT_COMMAND="_keypath_send_context${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
```

## Implementation Priority

1. **Layer 4: tmux integration** (Highest value, cleanest integration)
   - Power users spend significant time in tmux
   - tmux has excellent hook support
   - Modes are well-defined (normal, copy, command)

2. **Layer 3: Shell integration** (Broad coverage)
   - Covers the "default" state when not in a specific tool
   - Git branch awareness enables git-specific hints
   - CWD enables project-aware keymaps

3. **Layer 2: Keystroke pattern detection** (Enhancement/fallback)
   - Improves experience with zero configuration
   - Useful for tools without explicit integration
   - Lower priority—nice to have, not essential

## Scalability Considerations

### Which Tools Warrant Deep Integration?

Focus on tools that:
1. Have distinct modes with different keybindings (tmux, vim)
2. Are used for extended periods (terminal, editor)
3. Have hook/event systems for integration (tmux, neovim)

Shell integration provides broad baseline coverage; add deep integration only for frequently-used tools.

### User Configuration Approach

KeyPath should support user-defined context sources:

```json
{
  "context_sources": {
    "tmux": {
      "enabled": true,
      "hint_layer": "tmux-commands"
    },
    "custom-tool": {
      "enabled": true,
      "hint_layer": "custom-layer"
    }
  }
}
```

### Future Extensibility

The context protocol is intentionally flexible:
- `source` field identifies the tool (no registry required)
- `state` field is a freeform object (tool-specific)
- New tools can integrate without KeyPath changes
- KeyPath can ignore unknown sources gracefully

## Security Considerations

The TCP server (port 37001) listens on localhost only. Context updates do not execute code—they only update state used for display purposes.

See `KanataTCPClient.swift` for security notes on the TCP protocol.

## Related Documentation

- [Architecture Overview](./overview.md)
- [ADR-013: TCP Without Auth](../adr/adr-013-tcp-without-auth.md)
- [Action URI System](../ACTION_URI_SYSTEM.md)
