# Local Progress Dashboards

The local dashboard server exposes three related but visually distinct views:

- `keypath-test-automation-progress.html` is the live VM automation capability
  map.
- `keypath-github-issues-dashboard.html` is the open GitHub issue operations
  view. It refreshes through the authenticated local GitHub CLI every minute.
  If the repository reaches the 200-issue fetch ceiling, the dashboard marks
  its open count with `+` and states that only the first 200 are shown.
- `keypath-lab-state-dashboard.html` is the live operating view for the lab
  mini. It refreshes host readiness, USB keyboard state, leases, and VM
  resources every five seconds. Structured events from `keypath-lab` add the
  current stage, elapsed time, human handoff, blocker, next action, evidence,
  and cleanup transitions.

All pages include the same three-tab navigation. The automation dashboard keeps
its capability IDs and proven/active/queued vocabulary. The issue dashboard
uses GitHub issue numbers, repository styling, labels, and a bug-first work
queue. The Lab state view uses a dark operating-console treatment and represents
ephemeral resources and run transitions, so none of the three surfaces can be
mistaken for one another.

## Render both views

```bash
./Scripts/lab/render-progress-dashboard
./Scripts/lab/render-issue-dashboard
./Scripts/lab/render-lab-state-dashboard
```

## Run the local server

```bash
python3 Scripts/lab/progress-dashboard-server.py \
  --root "$PWD" \
  --state "$PWD/docs/testing/keypath-test-automation-state.json" \
  --port 8765
```

The server may be launched from a different worktree than the automation state
owner. Pass that owner's state file to `--state`; the server routes it at the
stable same-origin URL while keeping issue refresh state outside the worktree.
Live lab run state defaults to `/tmp/keypath-lab-state.json`, so normal
operation does not dirty the repository. Set `KEYPATH_LAB_DASHBOARD_STATE` for
both the server and `keypath-lab` when a different runtime path is needed.
