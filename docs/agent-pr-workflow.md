# Agent PR Workflow

End-to-end process for shepherding code from initial request through to a clean master. Every agent working on code changes must follow this workflow. The goal is zero lost work and a clean repo state at every stage.

## Phase 1: Setup

1. **Enter a worktree** — isolates your work from the user's working copy and other parallel agents. Verify you're in the worktree before editing files.
2. **Initialize submodules** if needed — worktrees don't automatically check out submodules. Run `git submodule update --init --recursive` before building.

## Phase 2: Development

3. **Do the work** — edit code, iterate with the user.
4. **Build** — `swift build` must pass before any commit.
5. **Test** — `swift test` must pass (all 532+ tests). Never commit code that breaks tests.
6. **Commit** — commit frequently as you work. Use descriptive messages. Include `Co-Authored-By` tag.

## Phase 3: PR Creation

7. **Squash commits** — `git reset --soft master && git commit` with a comprehensive message covering all changes.
8. **Push the branch** — `git push -u origin <branch-name>`.
9. **Link issues** — check if any open GitHub issues are addressed by this work (`gh issue list --state open`). Include `Fixes #NNN` in the PR body for each one so GitHub auto-closes them on merge.
10. **Create the PR** — `gh pr create` with a summary, `Fixes` references, and test plan. Return the URL to the user.

## Phase 4: Babysit the PR

11. **Wait for CI** — poll `gh pr checks <number>` until all checks complete. Don't guess — wait for actual results.
12. **Address review comments** — read `gh api repos/owner/repo/pulls/<number>/comments`, fix each issue, amend the commit, force-push.
13. **Resolve conflicts** — if master has moved ahead, `git fetch origin master && git merge origin/master`, resolve conflicts, commit the merge, push.
14. **Re-check CI** — after any push, wait for all checks to go green again.
15. **Repeat 11-14** until all checks pass and no unaddressed review comments remain.

## Phase 5: Merge

16. **Ask the user for permission to merge** — never merge without explicit approval.
17. **Merge** — `gh pr merge <number> --squash --delete-branch`. If git complains about the local branch being in use (worktree), that's fine — the merge happens on GitHub. The error about local branch deletion is cosmetic.
18. **Verify the merge** — `gh pr view <number> --json state` should show `"state": "MERGED"`.
19. **Verify issues closed** — for each `Fixes #NNN` reference, confirm the issue is now closed: `gh issue view <number> --json state`.

## Phase 6: Cleanup

20. **Exit the worktree** — `ExitWorktree` with `action: "remove"` and `discard_changes: true` (safe because all work is merged). This deletes the worktree directory and branch.
21. **Pull master** — `git pull` from the main repo directory. Verify it fast-forwards to include your merged PR. If it doesn't fast-forward, something went wrong — investigate before proceeding.
22. **Deploy from master** — run `SKIP_NOTARIZE=1 ./build.sh` (or `dd`) so the running app matches the merged code. This is critical — without this step, the user is running stale code and thinks the work is lost.
23. **Confirm to the user** — state explicitly: PR merged, issues closed, master pulled, deployed, worktree cleaned up.

## What Can Go Wrong

| Symptom | Cause | Prevention |
|---------|-------|------------|
| Work "disappears" after merge | Merged to GitHub but never pulled to local master, or deployed from worktree not master | Always do Phase 6 steps 21-22 |
| Issues stay open after merge | PR body didn't include `Fixes #NNN` keywords | Step 9: link issues before creating the PR |
| PR shows conflicts after merge | Another PR merged first, moving master ahead | Resolve conflicts before merging (step 13) |
| CI passes but app is broken | Tests don't cover the feature; only tested in worktree | Deploy from master (step 22) and have user verify |
| Worktree left behind | Agent exited without cleanup | Always exit worktree on completion |
| Stale build running | Deployed from worktree during dev, never redeployed from master | Step 22 is mandatory, not optional |
| Amending a commit after merge | Force-push after squash-merge creates a diverged branch | Never push after merge — go straight to cleanup |

## Non-Negotiable Rules

- **Never merge without user permission.** Even if CI is green and reviews are addressed.
- **Never skip the deploy-from-master step.** This is the #1 cause of "lost work" — the code is in GitHub but the local app is running old code.
- **Never leave a worktree behind.** Clean up on completion or abandonment.
- **Never force-push to master.** Only force-push to feature branches during PR iteration.
- **Always verify CI after every push.** Don't assume a previous green carries forward.
- **Always link issues.** If the work addresses an open issue, the PR must include `Fixes #NNN` so it auto-closes on merge.
