# Agent PR Invariants

What must be true at each phase boundary. The agent's job is to make these true and verify they are — the specific commands are implementation details.

## After Setup

- [ ] Working in an isolated worktree (not the user's checkout)
- [ ] Build succeeds from the worktree

## After Development

- [ ] `swift build` passes
- [ ] `swift test` passes (all tests, zero failures)
- [ ] Branch is current with `origin/master` before the final broad local gate
      (`git rev-list --left-right --count origin/master...HEAD` reports `0`
      as the first number)
- [ ] Changes are committed with descriptive messages

## After Development — Documentation Check

- [ ] If the change adds or modifies user-visible behavior: a guide exists in `guides/` (or an existing guide is updated)
- [ ] If the change adds integration/automation surface: developer docs updated in `docs/`
- [ ] If the change touches installer, repair, helper, launchd, SMAppService, VirtualHID, or Kanata runtime readiness: the affected row in `docs/process/installer-repair-state-matrix.md` is named in the PR summary or test plan
- [ ] No documentation needed for internal refactors, test-only changes, or bug fixes with no UX change

## After Thermonuclear Review

- [ ] `/thermo-nuclear-swift-review` run against the branch diff
- [ ] All CONFIRMED and PLAUSIBLE findings addressed or explicitly justified

## After PR Creation

- [ ] Single squashed commit on the branch
- [ ] Branch pushed to origin
- [ ] PR exists on GitHub with summary and test plan
- [ ] PR branch is not behind `master` before waiting on CI/Claude
- [ ] Every open issue addressed by this work has `Fixes #NNN` in the PR body

## Required Status Checks

`master` requires both **`build-and-test`** and **`code-quality`** (strict — branch must be up to date). `code-quality` enforces the swiftformat version pin and is gating (#649/#652). Docs-only PRs don't trigger `ci.yml` (it's `paths-ignore`'d); the `ci-docs.yml` companion reports both contexts as success so docs PRs aren't blocked (#650).

## After Babysitting

- [ ] All CI checks green
- [ ] Zero unaddressed review comments
- [ ] No merge conflicts with master
- [ ] Branch is still current with `master`; if not, update first and rerun checks
- [ ] User has approved the merge

## After Merge — The Completion Gate

All of these must be true before the agent reports "done." If any fails, fix it before proceeding.

```
PR state == MERGED
local master SHA == origin/master SHA
running app built from master (not worktree; release-candidate build unless explicitly dev-only)
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
