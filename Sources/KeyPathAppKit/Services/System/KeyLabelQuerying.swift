import Foundation

/// Protocol for querying key labels from the OS keyboard layout.
/// Production implementation wraps UCKeyTranslate; tests inject a mock.
protocol KeyLabelQuerying: Sendable {
    /// Returns base and shifted characters for the given keyCodes.
    func labels(for keyCodes: [UInt16]) -> [UInt16: (base: String, shifted: String)]
}
