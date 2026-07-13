# Resumable Scenario Runner

`Scripts/lab/scenario-runner` executes a scenario plan through verified,
durable checkpoints. It is the runner contract for scenarios that include an
installer action, approval, reboot, or other mutation that cannot be safely
repeated merely because the controller was interrupted.

## Plan contract

Each plan has a stable scenario name and ordered steps. Every step needs an
`action` command and a `verify` command. `verify` is the independently observed
postcondition, not a process-exit check from the action.

```json
{
  "schemaVersion": 1,
  "scenario": "repair-reinstall",
  "steps": [
    {
      "id": "repair-runtime",
      "action": ["/Applications/KeyPath.app/Contents/MacOS/keypath-cli", "system", "repair", "--json"],
      "verify": ["Scripts/lab/assert-runtime-ready"]
    }
  ]
}
```

Run it with lease-local artifact paths:

```bash
Scripts/lab/scenario-runner \
  --plan .keypath-lab/scenarios/repair-reinstall.json \
  --state .keypath-lab/scenario-output/repair-reinstall/run-state.json \
  --result .keypath-lab/scenario-output/repair-reinstall/result.json
```

The state file is atomically replaced after every transition. It records the
canonical digest of the plan, ordered step IDs, attempts, the current step, and
only verified checkpoints. A changed plan must use a new state path; it cannot
reuse an earlier checkpoint ledger.

## Resume behavior

The runner first executes the step's postcondition probe. If it passes, that
step is checkpointed and its action is not replayed.

If an earlier process died while an action was in flight, resume probes the
postcondition before doing anything else:

- If it now passes, the step is checkpointed as complete.
- If it is absent and the plan has no recovery path, the run becomes blocked.
  It writes a `harness-transport-failure` result explaining that the mutation
  is uncertain. It never replays the action.
- A plan may declare both `recovery` and `recoveryVerify`. Only after that
  recovery has reached its declared safe postcondition may the original action
  be tried again.

When an action exits successfully but its verified postcondition remains
absent, the runner records `keypath-product-failure`; product success is never
inferred from an action exit code.

The runner keeps command output under a `logs/` sibling of the state file. Plan
authors must keep commands and logs secret-safe: use `secure-dialog-input` for
password sheets and do not put credentials in a plan or command output.

## Integration rule

Scenario drivers own the product plan and postconditions. The runner owns only
checkpoint durability and failure ownership. A scenario must obtain approval
actions from `keypath-cli system inspect --json` `plannedRecipes` and
`userActionRequired`; it must not invent a second installer planner.
