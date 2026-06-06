# Agent PR Workflow

End-to-end process for shepherding code from initial request through to a clean master. Every agent working on code changes must follow this workflow. The goal is zero lost work and a clean repo state at every stage.

## Phase 1: Setup

1. **Enter a worktree** — isolates your work from the user's working copy and other parallel agents. Verify you're in the worktree before editing files.
2. **Initialize submodules** if needed — worktrees don't automatically check out submodules. Run `git submodule update --init --recursive` before building.

## Phase 2: Development

3. **Do the work** — edit code, iterate with the user.
4. **Build** — `swift build` must pass before any commit.
5. **Test** — `swift test` must pass (all 532+ tests). Never commit code that breaks tests. Iterate with `swift test --filter <area>` for speed; run the **full** suite once as the pre-push gate — the final full run is required, the repeated mid-iteration full runs are the waste.
6. **Commit** — commit frequently as you work. Use descriptive messages. Include `Co-Authored-By` tag.

## Phase 2.5: Thermonuclear Review

6b. **Run `/thermo-nuclear-swift-review`** — before creating the PR, run the thermonuclear review skill against the branch diff. Address all CONFIRMED and PLAUSIBLE findings before proceeding. This is not optional — no PR goes out without passing the thermonuclear bar.

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

### Velocity — risk-tier the babysit (don't poll when you don't need to)

Most PR clock-time is latency, not rigor. Cut the latency without dropping any gate:

- **Risk-tier the merge.** *Mechanical / low-logic* PRs (formatting, dead-code removal with a green suite, docs, config-only) — once local build + full test + lint pass, push and `gh pr merge <n> --auto --squash`, then move on instead of sitting in a poll loop. *Logic / hot-path* PRs (runtime behavior, lifecycle, concurrency, FFI/syscalls, anything subtle) — keep the full manual babysit **and read every review comment**. **Never auto-merge a logic/hot-path PR:** review tools post real bugs as **non-blocking comments while the check still goes green** (e.g. an EPERM liveness bug that the `claude-review` check passed but a Codex comment caught — auto-merge would have shipped it).
- **Parallelize independent PRs.** Open non-conflicting PRs together, let their CI overlap, merge each when green — don't run them strictly serially.
- **Front-load review.** For substantive PRs, run `/code-review` locally *before* opening, with a runtime-reality lens ("what does this call actually return in the real root/unprivileged deployment?").

## Phase 5: Merge

16. **Ask the user for permission to merge** — never merge without explicit approval.
17. **Merge** — `gh pr merge <number> --merge --delete-branch` unless the PR explicitly needs another merge mode. If multiple worktrees are active, prefer `gh pr merge <number> --repo malpern/KeyPath --merge --delete-branch` from outside the repo so `gh` does not try to switch a local worktree to `master`. If a local worktree error appears, verify GitHub state before retrying; the PR may already be merged.
18. **Verify the merge** — `gh pr view <number> --json state` should show `"state": "MERGED"`.
19. **Verify issues closed** — for each `Fixes #NNN` reference, confirm the issue is now closed: `gh issue view <number> --json state`.

## Phase 5.5: Publish Documentation

If the PR added or changed files in `guides/`:

19b. **Copy guides to gh-pages** — use the gh-pages worktree at `.worktrees/gh-pages` (or `Scripts/publish-guides.sh`). Copy new/changed `guides/*.md` files, update `docs.md` if new guides need links in the landing page.
19c. **Push gh-pages** — `cd .worktrees/gh-pages && git add -A && git commit -m "Publish <guide names>" && git push origin gh-pages`.

## Phase 6: Cleanup

20. **Exit the worktree** — `ExitWorktree` with `action: "remove"` and `discard_changes: true` (safe because all work is merged). This deletes the worktree directory and branch.
21. **Pull master** — `git fetch --prune origin && git pull --ff-only origin master` from the intended master worktree. Verify it fast-forwards to include your merged PR. If another worktree owns `master`, do the pull and deploy from that worktree.
22. **Deploy from master** — run `./Scripts/release-candidate.sh` so the running app matches merged master with a signed/notarized local build. For fast dev-only handoffs where notarization is explicitly unnecessary, use `./Scripts/quick-deploy.sh` and say that you did not produce a notarized build.
23. **Confirm to the user** — state explicitly: PR merged, issues closed, master pulled, deployed, worktree cleaned up.

## What Can Go Wrong

| Symptom | Cause | Prevention |
|---------|-------|------------|
| Work "disappears" after merge | Merged to GitHub but never pulled to local master, or deployed from worktree not master | Always do Phase 6 steps 21-22 |
| `gh pr merge` reports a local worktree error | The PR merged on GitHub, then `gh` tried to switch/delete a branch owned by another worktree | Verify `gh pr view <number> --json state,mergeCommit`, fetch/prune, then pull/deploy from the master worktree |
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
