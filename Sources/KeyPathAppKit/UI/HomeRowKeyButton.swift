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

    @AppStorage(KeymapPreferences.keymapIdKey) private var selectedKeymapId: String = LogicalKeymap.defaultId

    private var displayLabel: String {
        guard let keyCode = LogicalKeymap.keyCode(forQwertyLabel: key),
              let label = (LogicalKeymap.find(id: selectedKeymapId) ?? .qwertyUS)
                  .label(for: keyCode, includeExtraKeys: false)
        else {
            return key.uppercased()
        }
        return label.uppercased()
    }

    var body: some View {
        Button(action: action) {
            HomeRowKeyChipSmall(letter: displayLabel, symbol: modSymbol)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("rules-summary-home-row-key-button-\(key)")
        .accessibilityLabel("Customize \(displayLabel) key")
    }
}
