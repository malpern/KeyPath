use kanata_keyberon::action::{Action, SequenceEvent};
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

fn action_supported(action: &Action<'_, &CustomAction>, input: OsCode, usages: &[u32]) -> bool {
    match action {
        Action::NoOp
        | Action::Trans
        | Action::Src
        | Action::Layer(_)
        | Action::DefaultLayer(_)
        | Action::CancelSequences
        | Action::OneShotIgnoreEventsTicks(_)
        | Action::Repeat => true,
        Action::KeyCode(KeyCode::ErrorUndefined) => true, // Parser's unused-slot sentinel.
        Action::KeyCode(key) => key_supported(*key, usages) || OsCode::from(*key) == input,
        Action::MultipleKeyCodes(keys) => keys.iter().all(|key| key_supported(*key, usages)),
        Action::MultipleActions(actions) => {
            actions.iter().all(|a| action_supported(a, input, usages))
        }
        Action::HoldTap(ht) => [&ht.hold, &ht.tap, &ht.timeout_action]
            .iter()
            .all(|a| action_supported(a, input, usages)),
        Action::OneShot(os) => action_supported(os.action, input, usages),
        Action::TapDance(td) => td
            .actions
            .iter()
            .all(|a| action_supported(a, input, usages)),
        Action::Chords(chords) => chords
            .chords
            .iter()
            .all(|(_, a)| action_supported(a, input, usages)),
        Action::Fork(fork) => {
            action_supported(&fork.left, input, usages)
                && action_supported(&fork.right, input, usages)
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

    cfg.layout.b().layers.iter().all(|layer| layer.iter().enumerate().all(|(row, actions)| {
        actions.iter().enumerate().all(|(position, action)| {
            let input = OsCode::try_from(position).unwrap_or(OsCode::KEY_RESERVED);
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
            action_supported(action, input, usages)
        })
    }))
}
