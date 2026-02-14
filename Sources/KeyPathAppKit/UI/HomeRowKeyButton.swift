import KeyPathCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// Helper view for home row key button - extracted to reduce view body complexity
struct HomeRowKeyButton: View {
    let key: String
    let modSymbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HomeRowKeyChipSmall(letter: key.uppercased(), symbol: modSymbol)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("rules-summary-home-row-key-button-\(key)")
        .accessibilityLabel("Customize \(key.uppercased()) key")
    }
}
