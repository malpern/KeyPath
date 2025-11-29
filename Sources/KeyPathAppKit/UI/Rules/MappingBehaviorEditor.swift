import SwiftUI

// MARK: - Editor Mode

enum MappingEditorMode: String, CaseIterable {
    case simple = "Simple"
    case advanced = "Advanced"
}

// MARK: - Mapping Behavior Editor

/// Editor for configuring advanced key behaviors (tap-hold, tap-dance).
/// Displays a Simple/Advanced segmented control; Advanced mode shows the state grid and timing.
struct MappingBehaviorEditor: View {
    @Binding var output: String
    @Binding var behavior: MappingBehavior?

    @State private var mode: MappingEditorMode = .simple
    @State private var showTimingOverrides = false

    // Dual-role state (derived from behavior or defaults)
    @State private var tapAction: String = ""
    @State private var holdAction: String = ""
    @State private var tapTimeout: Int = 200
    @State private var holdTimeout: Int = 200
    @State private var activateHoldOnOtherKey: Bool = false
    @State private var quickTap: Bool = false

    // Tap-dance state
    @State private var tapDanceWindow: Int = 200
    @State private var tapDanceSteps: [TapDanceStep] = []

    // Which behavior type is selected in advanced mode
    @State private var behaviorType: BehaviorType = .dualRole

    enum BehaviorType: String, CaseIterable {
        case dualRole = "Tap / Hold"
        case tapDance = "Tap Dance"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Segmented control
            Picker("Mode", selection: $mode) {
                ForEach(MappingEditorMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { _, newMode in
                if newMode == .simple {
                    // Clear behavior when switching to simple
                    behavior = nil
                } else {
                    // Initialize from current output if switching to advanced
                    if tapAction.isEmpty {
                        tapAction = output
                    }
                    syncBehaviorFromState()
                }
            }

            if mode == .simple {
                simpleView
            } else {
                advancedView
            }
        }
        .onAppear {
            initializeFromBehavior()
        }
    }

    // MARK: - Simple View

    private var simpleView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Output")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("Configure the output key in the field above.")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.8))
        }
    }

    // MARK: - Advanced View

    private var advancedView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Behavior type picker
            Picker("Behavior", selection: $behaviorType) {
                ForEach(BehaviorType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: behaviorType) { _, _ in
                syncBehaviorFromState()
            }

            if behaviorType == .dualRole {
                dualRoleEditor
            } else {
                tapDanceEditor
            }
        }
    }

    // MARK: - Dual Role Editor

    private var dualRoleEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            // State grid
            GroupBox("Actions") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Tap")
                            .frame(width: 60, alignment: .leading)
                            .foregroundColor(.secondary)
                        TextField("e.g. a, esc", text: $tapAction)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: tapAction) { _, _ in syncBehaviorFromState() }
                    }
                    HStack {
                        Text("Hold")
                            .frame(width: 60, alignment: .leading)
                            .foregroundColor(.secondary)
                        TextField("e.g. lctl, lmet", text: $holdAction)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: holdAction) { _, _ in syncBehaviorFromState() }
                    }
                }
                .padding(.vertical, 4)
            }

            // Timing section
            GroupBox("Timing") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Tapping term")
                            .foregroundColor(.secondary)
                        Spacer()
                        Stepper(
                            "\(tapTimeout) ms",
                            value: $tapTimeout,
                            in: 50 ... 500,
                            step: 10
                        )
                        .onChange(of: tapTimeout) { _, _ in syncBehaviorFromState() }
                    }

                    DisclosureGroup("Per-state overrides", isExpanded: $showTimingOverrides) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Hold timeout")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Stepper(
                                    "\(holdTimeout) ms",
                                    value: $holdTimeout,
                                    in: 50 ... 500,
                                    step: 10
                                )
                                .controlSize(.small)
                                .onChange(of: holdTimeout) { _, _ in syncBehaviorFromState() }
                            }
                        }
                        .padding(.top, 4)
                    }
                    .font(.caption)
                }
                .padding(.vertical, 4)
            }

            // Behavior flags
            GroupBox("Options") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: $activateHoldOnOtherKey) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Activate hold on other key")
                            Text("Hold triggers when you press another key")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: activateHoldOnOtherKey) { _, _ in syncBehaviorFromState() }

                    Toggle(isOn: $quickTap) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Quick tap")
                            Text("Fast taps always register as tap")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: quickTap) { _, _ in syncBehaviorFromState() }
                }
                .padding(.vertical, 4)
            }

            // Kanata syntax preview
            kanataPreview
        }
    }

    // MARK: - Tap Dance Editor

    @ViewBuilder
    private var tapDanceEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Pattern Window") {
                HStack {
                    Text("Time to register taps")
                        .foregroundColor(.secondary)
                    Spacer()
                    Stepper(
                        "\(tapDanceWindow) ms",
                        value: $tapDanceWindow,
                        in: 100 ... 500,
                        step: 10
                    )
                    .onChange(of: tapDanceWindow) { _, _ in syncBehaviorFromState() }
                }
                .padding(.vertical, 4)
            }

            GroupBox("Steps") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(tapDanceSteps.indices, id: \.self) { index in
                        HStack {
                            Text(tapDanceSteps[index].label)
                                .frame(width: 80, alignment: .leading)
                                .foregroundColor(.secondary)
                                .font(.caption)
                            TextField("action", text: Binding(
                                get: { tapDanceSteps[index].action },
                                set: { newValue in
                                    tapDanceSteps[index].action = newValue
                                    syncBehaviorFromState()
                                }
                            ))
                            .textFieldStyle(.roundedBorder)

                            if tapDanceSteps.count > 1 {
                                Button {
                                    tapDanceSteps.remove(at: index)
                                    syncBehaviorFromState()
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if tapDanceSteps.count < 5 {
                        Button {
                            let labels = ["Single tap", "Double tap", "Triple tap", "Quad tap", "Quint tap"]
                            let nextLabel = labels[min(tapDanceSteps.count, labels.count - 1)]
                            tapDanceSteps.append(TapDanceStep(label: nextLabel, action: ""))
                        } label: {
                            Label("Add Step", systemImage: "plus.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }

            kanataPreview
        }
    }

    // MARK: - Kanata Preview

    private var kanataPreview: some View {
        GroupBox {
            HStack {
                Text("Kanata syntax:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(previewSyntax)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.accentColor)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 2)
        }
    }

    private var previewSyntax: String {
        guard let behavior = behavior else { return output }

        // Create a temporary mapping to render
        let mapping = KeyMapping(input: "x", output: output, behavior: behavior)
        return KanataBehaviorRenderer.render(mapping)
    }

    // MARK: - State Sync

    private func initializeFromBehavior() {
        guard let behavior = behavior else {
            mode = .simple
            return
        }

        mode = .advanced

        switch behavior {
        case let .dualRole(dr):
            behaviorType = .dualRole
            tapAction = dr.tapAction
            holdAction = dr.holdAction
            tapTimeout = dr.tapTimeout
            holdTimeout = dr.holdTimeout
            activateHoldOnOtherKey = dr.activateHoldOnOtherKey
            quickTap = dr.quickTap

        case let .tapDance(td):
            behaviorType = .tapDance
            tapDanceWindow = td.windowMs
            tapDanceSteps = td.steps
        }
    }

    private func syncBehaviorFromState() {
        guard mode == .advanced else {
            behavior = nil
            return
        }

        switch behaviorType {
        case .dualRole:
            guard !tapAction.isEmpty, !holdAction.isEmpty else {
                behavior = nil
                return
            }
            behavior = .dualRole(DualRoleBehavior(
                tapAction: tapAction,
                holdAction: holdAction,
                tapTimeout: tapTimeout,
                holdTimeout: holdTimeout,
                activateHoldOnOtherKey: activateHoldOnOtherKey,
                quickTap: quickTap
            ))

        case .tapDance:
            let validSteps = tapDanceSteps.filter { !$0.action.isEmpty }
            guard !validSteps.isEmpty else {
                behavior = nil
                return
            }
            behavior = .tapDance(TapDanceBehavior(
                windowMs: tapDanceWindow,
                steps: validSteps
            ))
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State var output = "esc"
        @State var behavior: MappingBehavior? = nil

        var body: some View {
            MappingBehaviorEditor(output: $output, behavior: $behavior)
                .padding()
                .frame(width: 400)
        }
    }
    return PreviewWrapper()
}

