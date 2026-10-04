# Session app-specific eligibility investigation

2026-10-03, bounded harness audit. App-specific mappings generate virtual-key
conditions and Kanata `switch` actions. The existing transaction tests use a
`test.app` keymap with `a` mapped to `b`, then add `c` mapped to `d`; app context
activates the generated virtual key through the runtime's TCP interface.

A parser-only probe against the freshly built integration bridge at
`/private/tmp/keypath-driverless-only/build/kanata-host-bridge/libkeypath_kanata_host_bridge.dylib`
accepted this Kanata configuration but rejected its session eligibility:

```lisp
(defvirtualkeys vk_test XX)
(defalias kp-a (switch ((input virtual vk_test)) b break () a break))
(defsrc a)
(deflayer base @kp-a)
```

The probe supplied the exact current `SessionKeyMap` usage set excluding Caps
Lock usage 57. It started no runtime, captured no OS input and posted no events.
This is evidence of the validator's current conservative action coverage, not
proof that app-specific switching requires a driver. `Action::Switch` evaluation
and virtual-key activation/output are under a separate engine review.

`AppKeymapSaveTests` now uses the shared fresh-bridge test fixture, preserving its
transaction acceptance expectations pending that review. The added unsupported
Unicode-output test requires refusal before any file changes, journal creation,
runtime reload or applied callback. Nested unsupported output must remain
rejected even if supported keyboard switching becomes eligible. A missing local
bridge skips bridge-dependent fixture cases with a message; an explicitly named
missing bridge fails. No installed-library fallback or production test bypass is
used.

Follow-up: narrow generated virtual-input switch support is now integrated; see
[engine diagnosis and proof](../bugs/session-app-virtual-switch.md). Real TCP
engine acceptance passed in the agent worktree. Integration bridge rebuild,
Swift transaction checks and signed physical acceptance remain pending; the
original rejected probe above records the pre-fix behavior.
