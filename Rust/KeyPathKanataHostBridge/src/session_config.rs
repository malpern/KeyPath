use kanata_keyberon::action::{switch::OpCode, Action, ReleasableState, SequenceEvent};
use kanata_keyberon::key_code::KeyCode;
use kanata_parser::cfg::Cfg;
use kanata_parser::custom_action::CustomAction;
use kanata_parser::keys::{OsCode, PageCode};

fn key_supported(key: KeyCode, usages: &[u32]) -> bool {
    let code: OsCode = key.into();
    PageCode::try_from(code).is_ok_and(|pc| pc.page == 7 && usages.contains(&pc.code))
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
    managed_caps: bool,
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
        Action::Trans | Action::Src | Action::Repeat => !managed_caps,
        // Releasing a layer changes keyberon state only. Release-key remains
        // unavailable; it has different emitted-key ownership semantics.
        Action::ReleaseState(ReleasableState::Layer(_)) => true,
        Action::KeyCode(KeyCode::ErrorUndefined) => true, // Parser's unused-slot sentinel.
        Action::KeyCode(key) => {
            let output = OsCode::from(*key);
            (!managed_caps || !matches!(output, OsCode::KEY_CAPSLOCK | OsCode::KEY_F18))
                && (key_supported(*key, usages) || output == input)
        }
        Action::MultipleKeyCodes(keys) => keys.iter().all(|key| key_supported(*key, usages)),
        Action::MultipleActions(actions) => actions
            .iter()
            .all(|a| action_supported(a, input, usages, virtual_inputs, managed_caps)),
        Action::HoldTap(ht) => [&ht.hold, &ht.tap, &ht.timeout_action]
            .iter()
            .all(|a| action_supported(a, input, usages, virtual_inputs, managed_caps)),
        Action::OneShot(os) => {
            action_supported(os.action, input, usages, virtual_inputs, managed_caps)
        }
        Action::TapDance(td) => td
            .actions
            .iter()
            .all(|a| action_supported(a, input, usages, virtual_inputs, managed_caps)),
        Action::Chords(chords) => chords
            .chords
            .iter()
            .all(|(_, a)| action_supported(a, input, usages, virtual_inputs, managed_caps)),
        Action::Fork(fork) => {
            action_supported(&fork.left, input, usages, virtual_inputs, managed_caps)
                && action_supported(&fork.right, input, usages, virtual_inputs, managed_caps)
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
                        && action_supported(branch, input, usages, virtual_inputs, managed_caps)
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
    if cfg.input_devices.is_some()
        || cfg.options.macos_opts.macos_dev_names_include.is_some()
        || cfg.options.macos_opts.macos_dev_names_exclude.is_some()
    {
        return false;
    }

    let virtual_inputs: Vec<u16> = cfg.fake_keys.values().map(|index| *index as u16).collect();
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
            action_supported(action, input, usages, &virtual_inputs, false)
        })
    }))
}

/// Explicit managed-Caps admission. The HID/CG transport owns logical Caps input
/// separately from the emitted key map; adding HID 57 to that map is never safe.
pub(crate) fn supported_with_managed_caps(cfg: &Cfg, output_usages: &[u32]) -> bool {
    use kanata_parser::cfg::Overrides;

    if cfg.input_devices.is_some()
        || cfg.options.macos_opts.macos_dev_names_include.is_some()
        || cfg.options.macos_opts.macos_dev_names_exclude.is_some()
        || cfg.overrides != Overrides::new(&[])
        || cfg.layout.b().chords_v2.is_some()
        || cfg.zippy.is_some()
        || cfg.options.start_alias.is_some()
        || !cfg.mapped_keys.contains(&OsCode::KEY_CAPSLOCK)
        || cfg.mapped_keys.contains(&OsCode::KEY_F18)
    {
        return false;
    }
    let usages: Vec<u32> = output_usages
        .iter()
        .copied()
        .filter(|usage| !matches!(usage, 57 | 109))
        .collect();
    let virtual_inputs: Vec<u16> = cfg.fake_keys.values().map(|index| *index as u16).collect();
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
                    && !cfg.mapped_keys.contains(&input)
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
                action_supported(action, input, &usages, &virtual_inputs, true)
            })
        })
    })
}

#[cfg(test)]
mod tests {
    use super::*;

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
    fn managed_caps_rejects_source_transparency_repeat_and_reserved_outputs() {
        for action in [
            "caps",
            "f18",
            "_",
            "use-defsrc",
            "rpt-any",
            "(multi esc caps)",
            "(tap-hold 200 200 esc caps)",
            "(tap-hold 200 200 esc f18)",
            "(tap-hold 200 200 caps lctl)",
            "(tap-hold-release-timeout 200 200 esc lctl caps)",
            "(tap-hold-release-timeout 200 200 esc lctl f18)",
            "(macro esc caps)",
            "(macro esc f18)",
            "(tap-dance 200 (esc caps))",
            "(one-shot 200 caps)",
            "(multi esc rpt-any)",
            "(multi esc use-defsrc)",
        ] {
            assert!(
                !managed(&format!("(defsrc caps)(deflayer base {action})")),
                "{action}"
            );
        }
        assert!(!managed("(defsrc caps a)(deflayer base esc caps)"));
        assert!(!managed(
            "(defchords grp 200 (x) caps)(defsrc caps)(deflayer base (chord grp x))"
        ));
        assert!(!managed(
            "(defvirtualkeys vk_bad f18)(defsrc caps)(deflayer base esc)"
        ));
        assert!(!managed(
            "(defcfg process-unmapped-keys yes)(defsrc caps)(deflayer base esc)"
        ));
        assert!(!managed("(defsrc caps f18)(deflayer base esc a)"));
        assert!(!managed("(defsrc caps f18)(deflayer base esc f18)"));
        assert!(!managed("(defsrc caps)(deflayer base esc)(deflayer nav _)"));
        assert!(!managed(
            "(defvirtualkeys vk_bad (macro caps))(defsrc caps)(deflayer base esc)"
        ));
        assert!(!managed("(defvirtualkeys vk_test XX)(defsrc caps)(deflayer base (switch ((input virtual vk_test)) esc break () caps break))"));
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
    fn managed_caps_refuses_global_overrides_and_chords_v2() {
        assert!(!managed(
            "(defoverrides (a) (caps))(defsrc caps a)(deflayer base esc a)"
        ));
        assert!(!managed(
            "(defoverrides (a) (b))(defsrc caps a)(deflayer base esc a)"
        ));
        assert!(!managed("(defcfg concurrent-tap-hold yes)(defchordsv2 (caps a) caps 100 all-released ())(defsrc caps a)(deflayer base esc a)"));
        assert!(!managed("(defcfg concurrent-tap-hold yes)(defchordsv2 (caps a) esc 100 all-released ())(defsrc caps a)(deflayer base esc a)"));
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
            "(switch ((input virtual vk_test)) volu break () b break)",
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
            ("(multi (release-layer nav) volu)", false),
            ("(multi (release-layer nav) (unicode λ))", false),
            ("(release-key lctl)", false),
            ("(release-key volu)", false),
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
        definitions.push_str("vk_media volu)(defsrc a)(deflayer base a)");
        let cfg = kanata_parser::cfg::new_from_str(&definitions, Default::default()).unwrap();
        assert!(!supported(&cfg, &[4, 5]));
    }

    #[test]
    fn session_virtual_switch_rejects_unsupported_virtual_key_action() {
        let cfg = kanata_parser::cfg::new_from_str("(defvirtualkeys vk_test volu)(defalias kp-a (switch ((input virtual vk_test)) b break () a break))(defsrc a)(deflayer base @kp-a)", Default::default()).unwrap();
        assert!(!supported(&cfg, &[4, 5]));
    }
}
