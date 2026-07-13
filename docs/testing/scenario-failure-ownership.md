# Scenario Failure Ownership

Every non-passing lab scenario writes `result.json` with one failure owner. The
classification prevents a selector, transport, provider, or environment problem
from being reported as a KeyPath defect.

## Contract

Use `Scripts/lab/scenario-result record` to write a result. A passing result has
no classification. A failed or blocked result requires a classification and the
step where it occurred.

The supported classifications are:

- `keypath-product-failure`: KeyPath claimed a completed action, but its
  independently observed postcondition is absent or disagrees.
- `harness-selector-failure`: the harness selected the wrong UI element or
  interpreted a valid UI state incorrectly.
- `harness-transport-failure`: delivery, screenshot, SSH, or RFB transport
  failed before the expected product action could be observed.
- `provider-failure`: the virtualization provider failed after a lease was
  admitted.
- `unsupported-os-selector`: a known OS-specific UI is not yet supported by
  the harness.
- `environment-precondition-failure`: a required lane, policy, account,
  capacity reservation, or other external prerequisite is absent.

Attach only sanitized artifact-relative evidence paths. Do not put secrets,
credentials, or raw tool responses in `result.json`.

## Selector self-test

Run this in every runner test suite:

```bash
Scripts/lab/scenario-result selector-self-test \
  --output .keypath-lab/scenario-output/failure-ownership/result.json
```

It intentionally records a missing selector as
`harness-selector-failure`. This is the regression guard: a deliberate harness
mistake must never become a `keypath-product-failure`.
