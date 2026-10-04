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
) -> bool {
    match action {
        Action::NoOp
        | Action::Trans
        | Action::Src
        | Action::Layer(_)
        | Action::DefaultLayer(_)
        | Action::CancelSequences
        | Action::OneShotIgnoreEventsTicks(_)
        | Action::Repeat => true,
        // Releasing a layer changes keyberon state only. Release-key remains
        // unavailable; it has different emitted-key ownership semantics.
        Action::ReleaseState(ReleasableState::Layer(_)) => true,
        Action::KeyCode(KeyCode::ErrorUndefined) => true, // Parser's unused-slot sentinel.
        Action::KeyCode(key) => key_supported(*key, usages) || OsCode::from(*key) == input,
        Action::MultipleKeyCodes(keys) => keys.iter().all(|key| key_supported(*key, usages)),
        Action::MultipleActions(actions) => actions
            .iter()
            .all(|a| action_supported(a, input, usages, virtual_inputs)),
        Action::HoldTap(ht) => [&ht.hold, &ht.tap, &ht.timeout_action]
            .iter()
            .all(|a| action_supported(a, input, usages, virtual_inputs)),
        Action::OneShot(os) => action_supported(os.action, input, usages, virtual_inputs),
        Action::TapDance(td) => td
            .actions
            .iter()
            .all(|a| action_supported(a, input, usages, virtual_inputs)),
        Action::Chords(chords) => chords
            .chords
            .iter()
            .all(|(_, a)| action_supported(a, input, usages, virtual_inputs)),
        Action::Fork(fork) => {
            action_supported(&fork.left, input, usages, virtual_inputs)
                && action_supported(&fork.right, input, usages, virtual_inputs)
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
                    generated_condition && action_supported(branch, input, usages, virtual_inputs)
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
            action_supported(action, input, usages, &virtual_inputs)
        })
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

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
