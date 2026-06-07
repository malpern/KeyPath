enum TapHoldLabelPrecedence {
    /// Returns true when the idle tap label only repeats information already shown on the key.
    ///
    /// Logical and physical labels both participate because the overlay can render remapped
    /// layouts: `baseLabel` reflects the selected logical keymap, while `keyLabel` preserves the
    /// physical keycap label. If either already matches, showing the tap label would not add useful
    /// visual information, so HRM hold modifiers should take precedence.
    static func idleLabelAddsNoNewVisualInformation(
        _ tapHoldIdleLabel: String,
        baseLabel: String,
        keyLabel: String
    ) -> Bool {
        tapHoldIdleLabel.uppercased() == baseLabel.uppercased()
            || tapHoldIdleLabel.uppercased() == keyLabel.uppercased()
    }

    static func idleLabelMatchesBase(_ tapHoldIdleLabel: String, baseLabel: String, keyLabel: String) -> Bool {
        idleLabelAddsNoNewVisualInformation(tapHoldIdleLabel, baseLabel: baseLabel, keyLabel: keyLabel)
    }
}
