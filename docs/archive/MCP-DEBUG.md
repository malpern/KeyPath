# Linear MCP Debug Notes

## Context
- Date: 2026-02-05
- Repo: /Users/malpern/local-code/KeyPath
- Goal: Use Linear MCP tools from Codex for issue updates/comments.
- Actual outcome: Linear MCP tool calls fail consistently; direct Linear GraphQL API works using agent token from macOS Keychain.

## Current Symptoms
- Linear MCP tool calls fail with:
  - `Invalid tools/call result`
  - payload validation errors (`invalid_union`) indicating content shape mismatch.
- Reproducible with `mcp__linear__linear_search_issues`.

## Representative Error Shape
- `tools/call failed: Mcp error: -32602`
- `Invalid tools/call result`
- Validation path includes: `content[0]`
- Expected content includes text/resource/audio/image union forms, but returned data does not satisfy schema.

## What Was Attempted
1. Re-auth Linear MCP (`codex mcp login linear`).
2. Restart Codex session.
3. Retry Linear MCP search call.
4. Result: same schema/union validation failure.

## Confirmed Working Fallback
- Direct Linear GraphQL API calls using bearer token from Keychain service `LINEAR_AGENT_TOKEN`.
- Example completed action:
  - Updated `MAL-70` to `Done`.
  - Added completion comment with build/test + commit context.

## Related API Notes
- `issueSearch` endpoint is deprecated in this workspace.
- Use `issues(filter: ...)` instead.

## Local Token Handling
- Token source: macOS Keychain item service `LINEAR_AGENT_TOKEN`.
- Runtime env for app-launched Codex set via:
  - `launchctl setenv LINEAR_AGENT_TOKEN <token>`
- Verified via:
  - `launchctl getenv LINEAR_AGENT_TOKEN`

## Suggested Next Investigation Steps
1. Verify Linear MCP server/tool version and response schema compatibility with current Codex MCP client.
2. Capture raw MCP response body for a failing call to compare with expected tool-content schema.
3. Check whether this failure is specific to this workspace account/config or general across workspaces.
4. If available, test an alternate transport mode/config for Linear MCP.
5. Keep direct API fallback until MCP content schema mismatch is resolved.

## Temporary Operating Mode
- For Linear updates during refactor milestones:
  - Use direct GraphQL API with `LINEAR_AGENT_TOKEN` from Keychain.
  - Continue writing completion metadata (state changes + comments) through fallback path.
