use kanata_keyberon::action::{switch::OpCode, Action, ReleasableState, SequenceEvent};
use kanata_keyberon::key_code::KeyCode;
use kanata_parser::cfg::Cfg;
use kanata_parser::custom_action::CustomAction;
use kanata_parser::keys::{OsCode, PageCode};

fn key_supported(key: KeyCode, usages: &[u32]) -> bool {
    oscode_supported(key.into(), usages)
}

/// Consumer-page (0x0C) usages the session worker posts as macOS
/// system-defined media events (docs/architecture/driverless-media-keys.md
/// §Recommendation): volume up/down/mute, brightness up/down, play/pause,
/// next/previous, fast-forward/rewind. Fixed by the worker's code, not by the
/// host's keyboard map, so it is a constant here rather than a parameter.
pub(crate) const CONSUMER_OUTPUT_CODES: [u32; 10] =
    [0xE9, 0xEA, 0xE2, 0x6F, 0x70, 0xCD, 0xB5, 0xB6, 0xB3, 0xB4];

/// The one output rule: keyboard page (7) and in the host's key map, or one
/// of the consumer-page media keys the worker can post. Everything else (Fn,
/// other consumer usages) is refused.
fn oscode_supported(code: OsCode, usages: &[u32]) -> bool {
    PageCode::try_from(code).is_ok_and(|pc| {
        (pc.page == 7 && usages.contains(&pc.code))
            || (pc.page == 0x0C && CONSUMER_OUTPUT_CODES.contains(&pc.code))
    })
}

/// Outputs the session can emit: the host's key map plus native Caps Lock,
/// which SessionCapsLockOutput posts independently of physical Caps capture.
fn session_output_usages(usages: &[u32]) -> Vec<u32> {
    let mut output_usages = usages.to_vec();
    if !output_usages.contains(&57) {
        output_usages.push(57);
    }
    output_usages
}

/// Whether the session can emit the Kanata key `name` as an output, under the
/// same rule `supported` applies. `None` when Kanata does not know the name.
pub(crate) fn output_key_name_supported(name: &str, usages: &[u32]) -> Option<bool> {
    let code = kanata_parser::keys::str_to_oscode(name)?;
    Some(oscode_supported(code, &session_output_usages(usages)))
}

fn custom_supported(action: &CustomAction) -> bool {
    matches!(
        action,
        CustomAction::PushMessage(_)
            | CustomAction::FakeKey { .. }
            | CustomAction::FakeKeyOnRelease { .. }
            | CustomAction::FakeKeyOnIdle(_)
            | CustomAction::FakeKeyOnPhysicalIdle(_)
            | CustomAction::FakeKeyHoldForDuration(_)
            | CustomAction::Delay(_)
            | CustomAction::DelayOnRelease(_)
            | CustomAction::ReverseReleaseOrder
            | CustomAction::CancelMacroOnRelease
            | CustomAction::CancelMacroOnNextPress(_)
            | CustomAction::SequenceCancel
    )
}

fn action_supported(
    action: &Action<'_, &CustomAction>,
    input: OsCode,
    usages: &[u32],
    virtual_inputs: &[u16],
    reserved: Option<OsCode>,
) -> bool {
    match action {
        Action::NoOp
        | Action::Layer(_)
        | Action::DefaultLayer(_)
        | Action::CancelSequences
        | Action::OneShotIgnoreEventsTicks(_) => true,
        // Src and transparency can resolve using a replay/virtual coordinate,
        // and Repeat can replay such an action at a different coordinate. A
        // managed profile cannot prove these safe from the defining input alone.
        Action::Trans | Action::Src | Action::Repeat => reserved.is_none(),
        // Releasing a layer changes keyberon state only. Release-key remains
        // unavailable; it has different emitted-key ownership semantics.
        Action::ReleaseState(ReleasableState::Layer(_)) => true,
        Action::KeyCode(KeyCode::ErrorUndefined) => true, // Parser's unused-slot sentinel.
        Action::KeyCode(key) => {
            let output = OsCode::from(*key);
            reserved != Some(output) && (key_supported(*key, usages) || output == input)
        }
        Action::MultipleKeyCodes(keys) => keys.iter().all(|key| key_supported(*key, usages)),
        Action::MultipleActions(actions) => actions
            .iter()
            .all(|a| action_supported(a, input, usages, virtual_inputs, reserved)),
        Action::HoldTap(ht) => [&ht.hold, &ht.tap, &ht.timeout_action]
            .iter()
            .all(|a| action_supported(a, input, usages, virtual_inputs, reserved)),
        Action::OneShot(os) => action_supported(os.action, input, usages, virtual_inputs, reserved),
        Action::TapDance(td) => td
            .actions
            .iter()
            .all(|a| action_supported(a, input, usages, virtual_inputs, reserved)),
        Action::Chords(chords) => chords
            .chords
            .iter()
            .all(|(_, a)| action_supported(a, input, usages, virtual_inputs, reserved)),
        Action::Fork(fork) => {
            action_supported(&fork.left, input, usages, virtual_inputs, reserved)
                && action_supported(&fork.right, input, usages, virtual_inputs, reserved)
        }
        Action::Switch(switch) => {
            // AppConfigGenerator emits one active virtual-input predicate per
            // case, followed by an unconditional fallback. These conditions
            // observe layout state only; callbacks/commands and device-history
            // conditions remain outside this deliberately narrow profile.
            switch.init_fn.is_none()
                && switch.callbacks.is_empty()
                && switch.cases.iter().all(|(condition, branch, _)| {
                    let generated_condition = condition.is_empty()
                        || virtual_inputs.iter().any(|index| {
                            let (op, coord) = OpCode::new_active_input((
                                kanata_parser::cfg::FAKE_KEY_ROW,
                                *index,
                            ));
                            *condition == [op, coord]
                        });
                    generated_condition
                        && action_supported(branch, input, usages, virtual_inputs, reserved)
                })
        }
        Action::Custom(custom) => custom_supported(custom),
        Action::Sequence { events } | Action::RepeatableSequence { events } => {
            events.iter().all(|e| match e {
                SequenceEvent::Press(key)
                | SequenceEvent::Release(key)
                | SequenceEvent::Tap(key) => key_supported(*key, usages),
                SequenceEvent::Custom(custom) => custom_supported(custom),
                SequenceEvent::NoOp | SequenceEvent::Delay { .. } | SequenceEvent::Complete => true,
                _ => false,
            })
        }
        // New/unsupported action variants stay unavailable until their output
        // semantics are implemented and exercised with physical keys.
        _ => false,
    }
}

pub(crate) fn supported(cfg: &Cfg, usages: &[u32]) -> bool {
    use kanata_parser::cfg::Overrides;
    if cfg.input_devices.is_some()
        || cfg.options.macos_opts.macos_dev_names_include.is_some()
        || cfg.options.macos_opts.macos_dev_names_exclude.is_some()
        || cfg.overrides != Overrides::new(&[])
        || cfg.zippy.is_some()
        || cfg.options.start_alias.is_some()
    {
        return false;
    }

    // Native Caps output is handled by SessionCapsLockOutput independently
    // of physical Caps capture. Never add it to the input eligibility set.
    let output_usages = session_output_usages(usages);
    let virtual_inputs: Vec<u16> = cfg.fake_keys.values().map(|index| *index as u16).collect();
    // Chords v2 store actions outside the layer tree. Check captured inputs
    // and recursively validate their separately stored output actions.
    if let Some(chords) = cfg.layout.b().chords_v2.as_ref() {
        for entry in chords.chords().mapping.values() {
            for chord in &entry.chords {
                if !chord.participating_keys.iter().all(|raw| {
                    OsCode::try_from(usize::from(*raw)).ok().is_some_and(|key| {
                        cfg.mapped_keys.contains(&key)
                            && PageCode::try_from(key)
                                .is_ok_and(|pc| pc.page == 7 && usages.contains(&pc.code))
                    })
                }) || !action_supported(
                    chord.action,
                    OsCode::KEY_RESERVED,
                    &output_usages,
                    &virtual_inputs,
                    None,
                ) {
                    return false;
                }
            }
        }
    }
    cfg.layout.b().layers.iter().all(|layer| layer.iter().enumerate().all(|(row, actions)| {
        actions.iter().enumerate().all(|(position, action)| {
            // Only physical rows have an unchanged-input exemption. A virtual
            // index is not an OsCode even when their numeric values coincide.
            let input = if row == 0 {
                OsCode::try_from(position).unwrap_or(OsCode::KEY_RESERVED)
            } else {
                OsCode::KEY_RESERVED
            };
            if row == 0 && cfg.mapped_keys.contains(&input) {
                let physical_supported = PageCode::try_from(input)
                    .is_ok_and(|pc| pc.page == 7 && usages.contains(&pc.code));
                if !physical_supported {
                    // Unknown physical inputs and Caps Lock can only pass
                    // through unchanged; session capture cannot remap them.
                    let allowed = matches!(action, Action::KeyCode(key) if OsCode::from(*key) == input)
                        || matches!(action, Action::Trans | Action::Src | Action::KeyCode(KeyCode::ErrorUndefined))
                        || (input == OsCode::KEY_RESERVED && matches!(action, Action::NoOp));
                    return allowed;
                }
            }
            action_supported(action, input, &output_usages, &virtual_inputs, None)
        })
    }))
}

/// The managed-Caps intermediate keys (F13-F20) by keyboard-page usage. The
/// event tap cannot see F21-F24, so they are never an intermediate.
pub(crate) fn intermediate_key(usage: u32) -> Option<OsCode> {
    Some(match usage {
        104 => OsCode::KEY_F13,
        105 => OsCode::KEY_F14,
        106 => OsCode::KEY_F15,
        107 => OsCode::KEY_F16,
        108 => OsCode::KEY_F17,
        109 => OsCode::KEY_F18,
        110 => OsCode::KEY_F19,
        111 => OsCode::KEY_F20,
        _ => return None,
    })
}

/// Explicit managed-Caps admission with F18 as the intermediate.
#[cfg(test)]
pub(crate) fn supported_with_managed_caps(cfg: &Cfg, output_usages: &[u32]) -> bool {
    supported_with_managed_caps_reserving(cfg, output_usages, 109)
}

/// Explicit managed-Caps admission. The HID/CG transport owns logical Caps input
/// separately from the emitted key map; adding HID 57 to that map is never safe.
/// `reserved_usage` is the intermediate Caps travels as; the profile may
/// neither read nor emit it.
pub(crate) fn supported_with_managed_caps_reserving(
    cfg: &Cfg,
    output_usages: &[u32],
    reserved_usage: u32,
) -> bool {
    use kanata_parser::cfg::Overrides;
    let Some(reserved) = intermediate_key(reserved_usage) else {
        return false;
    };

    if cfg.input_devices.is_some()
        || cfg.options.macos_opts.macos_dev_names_include.is_some()
        || cfg.options.macos_opts.macos_dev_names_exclude.is_some()
        || cfg.overrides != Overrides::new(&[])
        || cfg.zippy.is_some()
        || cfg.options.start_alias.is_some()
        || !cfg.source_keys.contains(&OsCode::KEY_CAPSLOCK)
        || cfg.source_keys.contains(&reserved)
    {
        return false;
    }
    let usages: Vec<u32> = output_usages
        .iter()
        .copied()
        .filter(|usage| *usage != reserved_usage)
        .collect();
    let mut usages = usages;
    if !usages.contains(&57) {
        usages.push(57);
    }
    let virtual_inputs: Vec<u16> = cfg.fake_keys.values().map(|index| *index as u16).collect();
    // Chords v2 live outside the layer action tree. Validate both the physical
    // participant inputs and each separately stored chord action before launch.
    if let Some(chords) = cfg.layout.b().chords_v2.as_ref() {
        for entry in chords.chords().mapping.values() {
            for chord in &entry.chords {
                if !chord.participating_keys.iter().all(|raw| {
                    OsCode::try_from(usize::from(*raw)).ok().is_some_and(|key| {
                        cfg.mapped_keys.contains(&key)
                            && (key == OsCode::KEY_CAPSLOCK
                                || PageCode::try_from(key)
                                    .is_ok_and(|pc| pc.page == 7 && usages.contains(&pc.code)))
                    })
                }) || !action_supported(
                    chord.action,
                    OsCode::KEY_RESERVED,
                    &usages,
                    &virtual_inputs,
                    Some(reserved),
                ) {
                    return false;
                }
            }
        }
    }
    cfg.layout.b().layers.iter().all(|layer| {
        layer.iter().enumerate().all(|(row, actions)| {
            actions.iter().enumerate().all(|(position, action)| {
                let input = if row == 0 {
                    OsCode::try_from(position).unwrap_or(OsCode::KEY_RESERVED)
                } else {
                    OsCode::KEY_RESERVED
                };
                // Kanata generates identity/transparent slots outside mapped
                // physical input. They cannot be processed by captured input;
                // repeat is refused globally, so cannot replay them either.
                if row == 0
                    && !cfg.source_keys.contains(&input)
                    && (matches!(action, Action::KeyCode(key) if OsCode::from(*key) == input)
                        || matches!(action, Action::Trans))
                {
                    return true;
                }
                if row == 0
                    && cfg.mapped_keys.contains(&input)
                    && input != OsCode::KEY_CAPSLOCK
                    && !PageCode::try_from(input)
                        .is_ok_and(|pc| pc.page == 7 && usages.contains(&pc.code))
                {
                    return matches!(action, Action::KeyCode(key) if OsCode::from(*key) == input)
                        || matches!(action, Action::KeyCode(KeyCode::ErrorUndefined))
                        || (input == OsCode::KEY_RESERVED && matches!(action, Action::NoOp));
                }
                action_supported(action, input, &usages, &virtual_inputs, Some(reserved))
            })
        })
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Keyboard-page usages the Swift host passes (SessionKeyMap minus Caps):
    /// letters, F1, F12, Home, Delete Forward. Enough to pin the rule.
    const HOST: &[u32] = &[4, 58, 69, 74, 76];

    #[test]
    fn output_key_names_follow_the_session_output_rule() {
        // Keyboard page and in the host map.
        assert_eq!(output_key_name_supported("a", HOST), Some(true));
        assert_eq!(output_key_name_supported("f1", HOST), Some(true));
        assert_eq!(output_key_name_supported("home", HOST), Some(true));
        // Native Caps is always an output, even though the host omits it.
        assert_eq!(output_key_name_supported("caps", HOST), Some(true));
        // Consumer page: the media and brightness keys the worker posts.
        for name in [
            "volu", "voldwn", "mute", "pp", "next", "prev", "brup", "brdown",
        ] {
            assert_eq!(output_key_name_supported(name, HOST), Some(true), "{name}");
        }
        // Consumer page, but not one the worker posts.
        assert_eq!(output_key_name_supported("calc", HOST), Some(false));
        // Keyboard page but outside the host map.
        assert_eq!(output_key_name_supported("f13", HOST), Some(false));
        // Not a Kanata key at all.
        assert_eq!(output_key_name_supported("not-a-key", HOST), None);
    }

    #[test]
    fn consumer_output_table_matches_kanata_names_and_inputs_stay_keyboard_only() {
        for (name, code) in [
            ("volu", 0xE9), ("vold", 0xEA), ("mute", 0xE2), ("brup", 0x6F), ("brdn", 0x70),
            ("pp", 0xCD), ("next", 0xB5), ("prev", 0xB6),
        ] {
            let os = kanata_parser::keys::str_to_oscode(name).unwrap();
            let pc = PageCode::try_from(os).unwrap();
            assert_eq!((pc.page, pc.code), (0x0C, code), "{name}");
            assert!(CONSUMER_OUTPUT_CODES.contains(&pc.code), "{name}");
        }
        // Until the tap reads media events, a media key is not an input.
        let cfg = kanata_parser::cfg::new_from_str("(defsrc volu)(deflayer base a)", Default::default()).unwrap();
        assert!(!supported(&cfg, HOST));
        // ...but it is an output anywhere a keyboard key would be.
        let cfg = kanata_parser::cfg::new_from_str("(defsrc a)(deflayer base volu)", Default::default()).unwrap();
        assert!(supported(&cfg, HOST));
    }

    #[test]
    fn native_caps_output_does_not_require_capturing_physical_caps() {
        for action in [
            "caps",
            "(tap-hold 200 200 esc caps)",
            "(macro caps)",
            "(tap-dance 200 (esc caps))",
        ] {
            let cfg = kanata_parser::cfg::new_from_str(
                &format!("(defsrc a)(deflayer base {action})"),
                Default::default(),
            )
            .unwrap();
            assert!(supported(&cfg, &[4, 41]), "{action}");
        }
        let input = kanata_parser::cfg::new_from_str(
            "(defsrc caps)(deflayer base esc)",
            Default::default(),
        )
        .unwrap();
        assert!(
            !supported(&input, &[4, 41]),
            "Output support must not authorize physical Caps capture"
        );
    }

    fn managed(text: &str) -> bool {
        let cfg = kanata_parser::cfg::new_from_str(text, Default::default()).unwrap();
        // Deliberately include both reserved usages to prove caller input cannot
        // authorize Caps/F18 output through aggregates or unchanged-key logic.
        supported_with_managed_caps(&cfg, &[4, 5, 41, 57, 109, 224])
    }

    #[test]
    fn managed_caps_accepts_only_explicit_safe_actions() {
        for action in [
            "esc",
            "lctl",
            "(tap-hold 200 200 esc lctl)",
            "(tap-hold 200 200 esc (layer-while-held nav))",
            "XX",
        ] {
            assert!(
                managed(&format!(
                    "(defsrc caps a)(deflayer base {action} a)(deflayer nav esc b)"
                )),
                "{action}"
            );
        }
        assert!(managed("(defvirtualkeys vk_test XX)(defsrc caps)(deflayer base (switch ((input virtual vk_test)) esc break () lctl break))"));
    }

    #[test]
    fn managed_caps_accepts_native_latch_outputs() {
        for action in [
            "caps",
            "(tap-hold 200 200 esc caps)",
            "(macro esc caps)",
            "(tap-dance 200 (esc caps))",
            "(one-shot 200 caps)",
            "(multi esc caps)",
        ] {
            assert!(
                managed(&format!("(defsrc caps)(deflayer base {action})")),
                "{action}"
            );
        }
    }

    #[test]
    fn managed_caps_rejects_source_transparency_repeat_and_reserved_outputs() {
        for action in [
            "f18",
            "_",
            "use-defsrc",
            "rpt-any",
            "(tap-hold 200 200 esc f18)",
            "(tap-hold-release-timeout 200 200 esc lctl f18)",
            "(macro esc f18)",
            "(multi esc rpt-any)",
            "(multi esc use-defsrc)",
        ] {
            assert!(
                !managed(&format!("(defsrc caps)(deflayer base {action})")),
                "{action}"
            );
        }
        assert!(managed("(defsrc caps a)(deflayer base esc caps)"));
        assert!(managed(
            "(defchords grp 200 (x) caps)(defsrc caps)(deflayer base (chord grp x))"
        ));
        assert!(!managed(
            "(defvirtualkeys vk_bad f18)(defsrc caps)(deflayer base esc)"
        ));
        assert!(managed(
            "(defcfg process-unmapped-keys yes)(defsrc caps)(deflayer base esc)"
        ));
        assert!(!managed(
            "(defcfg process-unmapped-keys yes)(defsrc caps f18)(deflayer base esc f18)"
        ));
        assert!(!managed(
            "(defcfg process-unmapped-keys yes)(defsrc a)(deflayer base a)"
        ));
        assert!(!managed("(defsrc caps f18)(deflayer base esc a)"));
        assert!(!managed("(defsrc caps f18)(deflayer base esc f18)"));
        assert!(!managed("(defsrc caps)(deflayer base esc)(deflayer nav _)"));
        assert!(managed(
            "(defvirtualkeys vk_bad (macro caps))(defsrc caps)(deflayer base esc)"
        ));
        assert!(managed("(defvirtualkeys vk_test XX)(defsrc caps)(deflayer base (switch ((input virtual vk_test)) esc break () caps break))"));
    }

    #[test]
    fn managed_caps_rejects_virtual_source_coordinates_and_non_caps_replay() {
        for reserved in [OsCode::KEY_CAPSLOCK, OsCode::KEY_F18] {
            let index = u16::from(reserved);
            let mut text = String::from("(defvirtualkeys ");
            for n in 0..index {
                text.push_str(&format!("vk_{n} XX "));
            }
            text.push_str("vk_reserved use-defsrc)(defsrc caps)(deflayer base esc)");
            assert!(!managed(&text), "virtual source index {index}");
        }
        assert!(!managed("(defsrc caps a)(deflayer base esc use-defsrc)"));
        assert!(!managed("(defsrc caps a)(deflayer base esc _)"));
        assert!(!managed("(defsrc caps a)(deflayer base esc rpt-any)"));
        assert!(!managed(
            "(defsrc caps a b)(deflayer base esc (multi a use-defsrc) rpt-any)"
        ));
    }

    #[test]
    fn managed_caps_refuses_global_overrides_and_unsafe_chords_v2() {
        assert!(!managed(
            "(defoverrides (a) (caps))(defsrc caps a)(deflayer base esc a)"
        ));
        assert!(!managed(
            "(defoverrides (a) (b))(defsrc caps a)(deflayer base esc a)"
        ));
        assert!(managed("(defcfg concurrent-tap-hold yes)(defchordsv2 (caps a) caps 100 all-released ())(defsrc caps a)(deflayer base esc a)"));
        assert!(managed("(defcfg concurrent-tap-hold yes)(defchordsv2 (caps a) esc 100 all-released ())(defsrc caps a)(deflayer base esc a)"));
        assert!(!managed("(defcfg concurrent-tap-hold yes)(defchordsv2 (caps a) f18 100 all-released ())(defsrc caps a)(deflayer base esc a)"));
        assert!(!managed("(defcfg concurrent-tap-hold yes)(defchordsv2 (caps a) (macro f18) 100 all-released ())(defsrc caps a)(deflayer base esc a)"));
        assert!(!managed("(defcfg concurrent-tap-hold yes)(defchordsv2 (caps a) caps 100 all-released ())(defsrc caps)(deflayer base esc)"));
    }

    #[test]
    fn chosen_intermediate_reserves_that_key_and_frees_f18() {
        let parse =
            |text: &str| kanata_parser::cfg::new_from_str(text, Default::default()).unwrap();
        let usages = [4, 5, 41, 57, 109, 110, 111, 224];
        // A profile using F18 cannot run with F18 as the intermediate, but can with F19.
        let f18_rule = parse("(defsrc caps f18)(deflayer base esc a)");
        assert!(!supported_with_managed_caps_reserving(
            &f18_rule, &usages, 109
        ));
        assert!(supported_with_managed_caps_reserving(
            &f18_rule, &usages, 110
        ));
        let f18_output = parse("(defsrc caps a)(deflayer base esc f18)");
        assert!(supported_with_managed_caps_reserving(
            &f18_output,
            &usages,
            110
        ));
        // The chosen key is reserved exactly as F18 was.
        assert!(!supported_with_managed_caps_reserving(
            &parse("(defsrc caps f19)(deflayer base esc a)"),
            &usages,
            110
        ));
        assert!(!supported_with_managed_caps_reserving(
            &parse("(defsrc caps a)(deflayer base esc f19)"),
            &usages,
            110
        ));
        assert!(!supported_with_managed_caps_reserving(
            &parse("(defsrc caps a)(deflayer base (tap-hold 200 200 esc f19) a)"),
            &usages,
            110
        ));
        // Only F13-F20 can be an intermediate.
        let plain = parse("(defsrc caps)(deflayer base esc)");
        for usage in [0, 57, 103, 112, 115] {
            assert!(
                !supported_with_managed_caps_reserving(&plain, &usages, usage),
                "{usage}"
            );
        }
        for usage in 104..=111 {
            assert!(
                supported_with_managed_caps_reserving(&plain, &usages, usage),
                "{usage}"
            );
        }
    }

    #[test]
    fn managed_caps_preserves_generated_unmapped_slots_and_old_admission() {
        let cfg =
            kanata_parser::cfg::new_from_str("(defsrc a)(deflayer base a)", Default::default())
                .unwrap();
        assert!(supported(&cfg, &[4]));
        assert!(!supported_with_managed_caps(&cfg, &[4]));
        let caps = kanata_parser::cfg::new_from_str(
            "(defsrc caps)(deflayer base esc)",
            Default::default(),
        )
        .unwrap();
        assert!(!supported(&caps, &[4, 41, 224]));
        assert!(supported_with_managed_caps(&caps, &[4, 41, 224]));
    }

    fn eligible(branch: &str, condition: &str) -> bool {
        let text = format!("(defvirtualkeys vk_test XX)(defalias kp-a (switch {condition} {branch} break () a break))(defsrc a)(deflayer base @kp-a)");
        let cfg = kanata_parser::cfg::new_from_str(&text, Default::default()).unwrap();
        supported(&cfg, &[4, 5])
    }

    #[test]
    fn session_virtual_switch_validates_every_nested_branch() {
        assert!(eligible("b", "((input virtual vk_test))"));
        assert!(eligible(
            "(switch ((input virtual vk_test)) b break () a break)",
            "((input virtual vk_test))"
        ));
        assert!(!eligible(
            "(switch ((input virtual vk_test)) calc break () b break)",
            "((input virtual vk_test))"
        ));
        assert!(!eligible("(unicode λ)", "((input virtual vk_test))"));
        assert!(!eligible("b", "((input real a))"));
        assert!(!eligible("b", "((input-history virtual vk_test 1))"));
    }

    #[test]
    fn layer_release_keeps_recursive_output_and_release_key_restrictions() {
        for (action, expected) in [
            ("(release-layer nav)", true),
            (
                "(multi (release-layer nav) XX (push-msg \"layer:base\"))",
                true,
            ),
            ("(multi (release-layer nav) calc)", false),
            ("(multi (release-layer nav) (unicode λ))", false),
            ("(release-key lctl)", false),
            ("(release-key calc)", false),
        ] {
            let cfg = kanata_parser::cfg::new_from_str(
                &format!(
                    "(defsrc a b)(deflayer base (layer-while-held nav) b)(deflayer nav _ {action})"
                ),
                Default::default(),
            )
            .unwrap();
            assert_eq!(supported(&cfg, &[4, 5, 224]), expected, "{action}");
        }
    }

    #[test]
    fn virtual_index_cannot_bypass_output_key_validation() {
        let index = u16::from(OsCode::KEY_VOLUMEUP);
        let mut definitions = String::from("(defvirtualkeys ");
        for n in 0..index {
            definitions.push_str(&format!("vk_{n} XX "));
        }
        definitions.push_str("vk_media calc)(defsrc a)(deflayer base a)");
        let cfg = kanata_parser::cfg::new_from_str(&definitions, Default::default()).unwrap();
        assert!(!supported(&cfg, &[4, 5]));
    }

    #[test]
    fn session_virtual_switch_rejects_unsupported_virtual_key_action() {
        let cfg = kanata_parser::cfg::new_from_str("(defvirtualkeys vk_test calc)(defalias kp-a (switch ((input virtual vk_test)) b break () a break))(defsrc a)(deflayer base @kp-a)", Default::default()).unwrap();
        assert!(!supported(&cfg, &[4, 5]));
    }

    #[test]
    fn legacy_session_simple_mapping() {
        let cfg =
            kanata_parser::cfg::new_from_str("(defsrc a)(deflayer base b)", Default::default())
                .unwrap();
        assert_eq!(supported(&cfg, &[4, 5, 41, 224]), true);
    }

    #[test]
    fn legacy_session_startup_unsupported() {
        let cfg = kanata_parser::cfg::new_from_str(
            "(defcfg alias-to-trigger-on-load boot)(defalias boot calc)(defsrc a)(deflayer base a)",
            Default::default(),
        )
        .unwrap();
        assert_eq!(supported(&cfg, &[4, 5, 41, 224]), false);
    }

    #[test]
    fn legacy_session_startup_opaque() {
        let cfg = kanata_parser::cfg::new_from_str(
            "(defcfg alias-to-trigger-on-load boot)(defalias boot b)(defsrc a)(deflayer base a)",
            Default::default(),
        )
        .unwrap();
        assert_eq!(supported(&cfg, &[4, 5, 41, 224]), false);
    }

    #[test]
    fn legacy_session_override_unsupported() {
        let cfg = kanata_parser::cfg::new_from_str(
            "(defoverrides (a) (calc))(defsrc a)(deflayer base a)",
            Default::default(),
        )
        .unwrap();
        assert_eq!(supported(&cfg, &[4, 5, 41, 224]), false);
    }

    #[test]
    fn legacy_session_override_opaque() {
        let cfg = kanata_parser::cfg::new_from_str(
            "(defoverrides (a) (b))(defsrc a)(deflayer base a)",
            Default::default(),
        )
        .unwrap();
        assert_eq!(supported(&cfg, &[4, 5, 41, 224]), false);
    }

    #[test]
    fn legacy_session_chord_unsupported() {
        let cfg = kanata_parser::cfg::new_from_str("(defcfg concurrent-tap-hold yes)(defchordsv2 (a b) calc 100 all-released ())(defsrc a b)(deflayer base a b)", Default::default()).unwrap();
        assert_eq!(supported(&cfg, &[4, 5, 41, 224]), false);
    }

    #[test]
    fn legacy_session_chord_nested_unsupported() {
        let cfg = kanata_parser::cfg::new_from_str("(defcfg concurrent-tap-hold yes)(defchordsv2 (a b) (macro calc) 100 all-released ())(defsrc a b)(deflayer base a b)", Default::default()).unwrap();
        assert_eq!(supported(&cfg, &[4, 5, 41, 224]), false);
    }

    #[test]
    fn legacy_session_chord_supported() {
        let cfg = kanata_parser::cfg::new_from_str("(defcfg concurrent-tap-hold yes)(defchordsv2 (a b) esc 100 all-released ())(defsrc a b)(deflayer base a b)", Default::default()).unwrap();
        assert_eq!(supported(&cfg, &[4, 5, 41, 224]), true);
    }

    #[test]
    fn legacy_session_chord_uncapturable_input() {
        let cfg = kanata_parser::cfg::new_from_str("(defcfg concurrent-tap-hold yes)(defchordsv2 (caps a) esc 100 all-released ())(defsrc caps a)(deflayer base caps a)", Default::default()).unwrap();
        assert_eq!(supported(&cfg, &[4, 5, 41, 224]), false);
    }
}
