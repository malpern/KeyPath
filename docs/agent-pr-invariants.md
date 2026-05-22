# Agent PR Invariants

What must be true at each phase boundary. The agent's job is to make these true and verify they are — the specific commands are implementation details.

## After Setup

- [ ] Working in an isolated worktree (not the user's checkout)
- [ ] Build succeeds from the worktree

## After Development

- [ ] `swift build` passes
- [ ] `swift test` passes (all tests, zero failures)
- [ ] Changes are committed with descriptive messages

## After Thermonuclear Review

- [ ] `/thermo-nuclear-swift-review` run against the branch diff
- [ ] All CONFIRMED and PLAUSIBLE findings addressed or explicitly justified

## After PR Creation

- [ ] Single squashed commit on the branch
- [ ] Branch pushed to origin
- [ ] PR exists on GitHub with summary and test plan
- [ ] Every open issue addressed by this work has `Fixes #NNN` in the PR body

## After Babysitting

- [ ] All CI checks green
- [ ] Zero unaddressed review comments
- [ ] No merge conflicts with master
- [ ] User has approved the merge

## After Merge — The Completion Gate

All of these must be true before the agent reports "done." If any fails, fix it before proceeding.

```
PR state == MERGED
local master SHA == origin/master SHA
running app built from master (not worktree)
linked issues state == CLOSED
no worktrees left for this branch
```

The agent must verify each assertion, not assume prior steps succeeded. A single verification block at the end catches everything — skipped steps, failed pushes, stale deploys.

## Why Invariants Over Checklists

Agents lose context in long conversations. A 23-step checklist works when followed perfectly but fails silently when step 20 is skipped. Invariants are self-healing: the verification gate at the end catches any gap regardless of how the agent got there.

The procedural workflow (`agent-pr-workflow.md`) is still useful as a reference for the *typical* path through these phases. But the invariants are what matter — they define "done" unambiguously.

## Non-Negotiable Rules

- **Never merge without user permission.**
- **The running app must match merged master.** This is the #1 cause of "lost work."
- **Never force-push to master.**
- **Always link and verify issues.**
- **Clean up worktrees.** No orphaned branches or directories.
