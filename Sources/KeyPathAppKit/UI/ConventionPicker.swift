import SwiftUI

// MARK: - Convention Picker

/// Native macOS segmented picker for key layout convention
struct ConventionPicker: View {
    let convention: WindowKeyConvention
    let onConventionChange: (WindowKeyConvention) -> Void

    @State private var localConvention: WindowKeyConvention

    init(convention: WindowKeyConvention, onConventionChange: @escaping (WindowKeyConvention) -> Void) {
        self.convention = convention
        self.onConventionChange = onConventionChange
        _localConvention = State(initialValue: convention)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Native macOS segmented control
            Picker("Key Layout", selection: $localConvention) {
                Text("Standard").tag(WindowKeyConvention.standard)
                Text("Vim").tag(WindowKeyConvention.vim)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("window-snapping-convention-picker")
            .accessibilityLabel("Key layout convention")
            .onChange(of: localConvention) { _, newValue in
                onConventionChange(newValue)
            }
            .onChange(of: convention) { _, newValue in
                localConvention = newValue
            }

            // Description
            Text(convention.description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
