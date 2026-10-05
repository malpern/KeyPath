# Experimental managed Caps parsed admission

The additive C entry point `keypath_kanata_bridge_validate_session_config_with_managed_caps`
accepts an explicit managed-Caps flag. False preserves the original validator and ABI.
True uses the actual Kanata parsed action tree and treats the supplied HID usages as
outputs. Logical Caps (HID 57) is admitted independently as mapped input. Caps and
F18 (HID 109) remain prohibited outputs even when supplied in the output usage array.

Managed admission requires mapped Caps, reserves mapped F18, and rejects source,
transparency and repeat at the Caps coordinate, including nested actions. Existing
recursive traversal validates tap, hold, timeout, macro, virtual-key, switch and
legacy chord branches. Generated unmapped identity slots do not count as meaningful
outputs. Nonempty global overrides, chords-v2, zippy and startup aliases are refused
until their independent execution paths can be proven safe. `process-unmapped-keys
yes` currently reserves F18 via `mapped_keys` and is conservatively refused.

Parser identity: Kanata fork `0853689f04d40f6b8d283fef80e34b3d53531b89`.
`Cfg.layout.src_keys` is generated for every OsCode, so it cannot establish explicit
defsrc membership. The proof uses `mapped_keys` and parsed actions without changing
configuration text. Focused Rust tests exercise both parsed actions and C API errors.
This is admission only; transport origin checks, session lifecycle and managed HID
restoration are separate integration obligations. No physical behavior was tested.
