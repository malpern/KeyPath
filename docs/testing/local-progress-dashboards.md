# Local Progress Dashboards

The local dashboard server exposes two related but visually distinct views:

- `keypath-test-automation-progress.html` is the live VM automation capability
  map.
- `keypath-github-issues-dashboard.html` is the open GitHub issue operations
  view. It refreshes through the authenticated local GitHub CLI every minute.
  If the repository reaches the 200-issue fetch ceiling, the dashboard marks
  its open count with `+` and states that only the first 200 are shown.

Both pages include the same two-tab navigation. The automation dashboard keeps
its capability IDs and proven/active/queued vocabulary. The issue dashboard
uses GitHub issue numbers, repository styling, labels, and a bug-first work
queue so the two surfaces cannot be mistaken for one another.

## Render both views

```bash
./Scripts/lab/render-progress-dashboard
./Scripts/lab/render-issue-dashboard
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
