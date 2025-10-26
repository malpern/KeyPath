import SwiftUI

struct RecordingSection: View {
    @ObservedObject var coordinator: RecordingCoordinator
    let onInputRecord: () -> Void
    let onOutputRecord: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            inputSection
            outputSection
        }
        .onAppear { coordinator.requestPlaceholders() }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Input Key")
                    .font(.headline)
                    .accessibilityIdentifier("input-key-label")

                Spacer()

                Button(action: {
                    PreferencesService.shared.applyMappingsDuringRecording.toggle()
                    coordinator.requestPlaceholders()
                }, label: {
                    let isOn = PreferencesService.shared.applyMappingsDuringRecording
                    Image(systemName: "app.background.dotted")
                        .font(.title2)
                        .foregroundColor(isOn ? .white : .blue)
                        .frame(width: 32, height: 32)
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                })
                .buttonStyle(.plain)
                .appSolidGlassButton(
                    tint: PreferencesService.shared.applyMappingsDuringRecording ? .blue : Color(NSColor.textBackgroundColor),
                    radius: 6
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.blue.opacity(0.25), lineWidth: 0.5)
                )
                .cornerRadius(6)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .help(PreferencesService.shared.applyMappingsDuringRecording
                    ? "Mappings ON: Recording shows effective (mapped) keys. Click to show raw keys."
                    : "Mappings OFF: Recording shows raw (physical) keys. Click to show mapped keys.")
                .accessibilityIdentifier("apply-mappings-toggle")
                .accessibilityLabel(PreferencesService.shared.applyMappingsDuringRecording
                    ? "Disable mappings during recording"
                    : "Enable mappings during recording")
                .padding(.trailing, 5)

                Button(action: {
                    coordinator.toggleSequenceMode()
                    coordinator.requestPlaceholders()
                }, label: {
                    Image(systemName: "list.number")
                        .font(.title2)
                        .foregroundColor(coordinator.isSequenceMode ? .white : .blue)
                        .frame(width: 32, height: 32)
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                })
                .buttonStyle(.plain)
                .appSolidGlassButton(tint: coordinator.isSequenceMode ? .blue : Color(NSColor.textBackgroundColor), radius: 6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.blue.opacity(0.25), lineWidth: 0.5)
                )
                .cornerRadius(6)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .help(coordinator.isSequenceMode ? "Capture sequences of keys" : "Capture key combos")
                .accessibilityIdentifier("sequence-mode-toggle")
                .accessibilityLabel(coordinator.isSequenceMode ? "Switch to combo mode" : "Switch to sequence mode")
                .accessibilityHint("Toggle between combo capture and sequence capture modes")
                .padding(.trailing, 5)
            }

            HStack {
                Text(coordinator.inputDisplayText())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .appFieldGlass(radius: 8, opacity: coordinator.isInputRecording() ? 0.16 : 0.06)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(coordinator.isInputRecording() ? Color.blue : Color.clear, lineWidth: 2)
                    )
                    .accessibilityIdentifier("input-key-display")
                    .accessibilityLabel("Input key")
                    .accessibilityValue(
                        coordinator.inputDisplayText().isEmpty
                            ? "No key recorded"
                            : "Key: \(coordinator.inputDisplayText())"
                    )
                    .id("\(coordinator.isInputRecording())-\(coordinator.inputDisplayText())")

                Button(action: {
                    AppLogger.shared.log("🖱️ [UI] Input record button tapped (isRecording=\(coordinator.isInputRecording()))")
                    onInputRecord()
                }, label: {
                    Image(systemName: coordinator.inputButtonIcon())
                        .font(.title2)
                })
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .appSolidGlassButton(tint: .accentColor, radius: 8)
                .foregroundColor(.white)
                .cornerRadius(8)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityIdentifier("input-key-record-button")
                .accessibilityLabel(coordinator.isInputRecording() ? "Stop recording input key" : "Record input key")
                .id(coordinator.isInputRecording())
                .accessibilityHint(
                    coordinator.isInputRecording()
                        ? "Stop recording the input key"
                        : "Start recording a key to remap"
                )
            }
        }
        .padding()
        // Transparent background for input section
        .accessibilityIdentifier("input-recording-section")
        .accessibilityLabel("Input key recording section")
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output Key")
                .font(.headline)
                .accessibilityIdentifier("output-key-label")

            HStack {
                Text(coordinator.outputDisplayText())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .appFieldGlass(radius: 8, opacity: coordinator.isOutputRecording() ? 0.16 : 0.06)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(coordinator.isOutputRecording() ? Color.blue : Color.clear, lineWidth: 2)
                    )
                    .accessibilityIdentifier("output-key-display")
                    .accessibilityLabel("Output key")
                    .accessibilityValue(
                        coordinator.outputDisplayText().isEmpty
                            ? "No key recorded"
                            : "Key: \(coordinator.outputDisplayText())"
                    )

                Button(action: {
                    AppLogger.shared.log("🖱️ [UI] Output record button tapped (isRecording=\(coordinator.isOutputRecording()))")
                    onOutputRecord()
                }, label: {
                    Image(systemName: coordinator.outputButtonIcon())
                        .font(.title2)
                })
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .appSolidGlassButton(tint: .accentColor, radius: 8)
                .foregroundColor(.white)
                .cornerRadius(8)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityIdentifier("output-key-record-button")
                .accessibilityLabel(coordinator.isOutputRecording() ? "Stop recording output key" : "Record output key")
                .accessibilityHint(
                    coordinator.isOutputRecording()
                        ? "Stop recording the output key"
                        : "Start recording the replacement key"
                )
            }
        }
        .padding()
        // Transparent background for output section
        .accessibilityIdentifier("output-recording-section")
        .accessibilityLabel("Output key recording section")
    }
}

