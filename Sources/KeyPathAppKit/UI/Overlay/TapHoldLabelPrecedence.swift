enum TapHoldLabelPrecedence {
    /// Suppress idle tap labels that only echo the base key so HRM hold modifiers can take precedence.
    static func idleLabelMatchesBase(_ tapHoldIdleLabel: String, baseLabel: String, keyLabel: String) -> Bool {
        tapHoldIdleLabel.uppercased() == baseLabel.uppercased()
            || tapHoldIdleLabel.uppercased() == keyLabel.uppercased()
    }
}
