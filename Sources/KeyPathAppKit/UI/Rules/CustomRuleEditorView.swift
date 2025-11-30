import KeyPathCore
import SwiftUI

struct CustomRuleEditorView: View {
    enum Mode {
        case create
        case edit
    }

    @Environment(\.dismiss) private var dismiss
    @State private var customName: String
    @State private var input: String
    @State private var output: String
    @State private var isEnabled: Bool
    @State private var behavior: MappingBehavior?
    @State private var showAdvanced: Bool = false
    @State private var isRecordingInput: Bool = false
    @State private var isRecordingOutput: Bool = false
    @State private var validationError: String?
    @State private var showDeleteConfirmation = false
    @State private var description: String = ""
    @State private var isEditingDescription: Bool = false
    @State private var isHoveringHeader: Bool = false

    // Advanced action states
    @State private var holdAction: String = ""
    @State private var tapDanceSteps: [(label: String, action: String)] = []
    @State private var tappingTerm: Int = 200
    @State private var isRecordingHold: Bool = false
    @State private var recordingTapDanceIndex: Int?

    // Conflict dialog state
    @State private var showConflictDialog: Bool = false
    @State private var pendingConflict: BehaviorConflict?

    // Hold behavior type (radio button selection)
    enum HoldBehaviorType: String, CaseIterable {
        case basic = "Basic"
        case triggerEarly = "Trigger early"
        case quickTap = "Quick tap"
        case customKeys = "Custom keys"

        var activateHoldOnOtherKey: Bool {
            self == .triggerEarly
        }

        var quickTapMode: Bool {
            self == .quickTap
        }

        var description: String {
            switch self {
            case .basic:
                "Hold activates after timeout. Best for beginners."
            case .triggerEarly:
                "Hold activates immediately when another key is pressed. Best for home-row mods."
            case .quickTap:
                "Fast taps always register as tap, even if another key was pressed. Prevents accidental holds."
            case .customKeys:
                "Only specific keys trigger early tap. For fine-tuned control."
            }
        }
    }

    @State private var holdBehavior: HoldBehaviorType = .basic
    @State private var customTapKeysText: String = "" // Comma or space separated keys

    // Progressive disclosure: advanced timing options
    @State private var showTimingAdvanced: Bool = false
    @State private var tapTimeout: Int = 200
    @State private var holdTimeout: Int = 200

    private var tapDanceStepLabels: [String] {
        ["Double Tap", "Triple Tap", "Quad Tap", "Quint Tap", "Sext Tap", "Sept Tap", "Oct Tap"]
    }

    /// Default tap dance steps with only Double Tap
    private var defaultTapDanceSteps: [(label: String, action: String)] {
        [(label: "Double Tap", action: "")]
    }

    private let existingRule: CustomRule?
    private let existingRules: [CustomRule]
    private let mode: Mode
    let onSave: (CustomRule) -> Void
    let onDelete: ((CustomRule) -> Void)?

    // Consistent sizing
    private let fieldHeight: CGFloat = 44
    private let buttonSize: CGFloat = 44
    private let cornerRadius: CGFloat = 8
    private let spacing: CGFloat = 16

    init(
        rule: CustomRule?,
        existingRules: [CustomRule] = [],
        onSave: @escaping (CustomRule) -> Void,
        onDelete: ((CustomRule) -> Void)? = nil
    ) {
        existingRule = rule
        self.existingRules = existingRules
        self.onSave = onSave
        self.onDelete = onDelete
        if let rule {
            _customName = State(initialValue: rule.title)
            _input = State(initialValue: rule.input)
            _output = State(initialValue: rule.output)
            _isEnabled = State(initialValue: rule.isEnabled)
            _behavior = State(initialValue: rule.behavior)
            _showAdvanced = State(initialValue: rule.behavior != nil)
            _description = State(initialValue: rule.notes ?? "")
            mode = .edit
        } else {
            _customName = State(initialValue: "")
            _input = State(initialValue: "")
            _output = State(initialValue: "")
            _description = State(initialValue: "")
            _isEnabled = State(initialValue: true)
            _behavior = State(initialValue: nil)
            _showAdvanced = State(initialValue: false)
            mode = .create
        }
    }

    private var displayName: String {
        if !customName.isEmpty {
            return customName
        } else if !input.isEmpty || !output.isEmpty {
            let inputDisplay = input.isEmpty ? "?" : KeyDisplayName.display(for: input)
            let outputDisplay = output.isEmpty ? "?" : KeyDisplayName.display(for: output)
            return "\(inputDisplay) → \(outputDisplay)"
        } else {
            return "New Rule"
        }
    }

    private var canSave: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header - simple title, no divider
            HStack {
                HStack(spacing: 8) {
                    KeyCapChip(text: input.isEmpty ? "?" : input)
                    Text("→")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    KeyCapChip(text: output.isEmpty ? "?" : output)
                }

                Text(displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.primary)

                // Description editor - appears on hover
                if isHoveringHeader || isEditingDescription || !description.isEmpty {
                    if isEditingDescription {
                        TextField("Description", text: $description, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.body.italic())
                            .foregroundColor(.secondary)
                            .lineLimit(1 ... 3)
                            .onSubmit {
                                isEditingDescription = false
                            }
                            .onExitCommand {
                                isEditingDescription = false
                            }
                            .frame(maxWidth: 200)
                            .onHover { hovering in
                                if hovering {
                                    NSCursor.iBeam.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                    } else {
                        HStack(spacing: 4) {
                            if !description.isEmpty {
                                Text(description)
                                    .font(.body.italic())
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                                    .onTapGesture {
                                        isEditingDescription = true
                                    }
                                    .onHover { hovering in
                                        if hovering {
                                            NSCursor.iBeam.push()
                                        } else {
                                            NSCursor.pop()
                                        }
                                    }
                            } else {
                                Text("Description")
                                    .font(.body.italic())
                                    .foregroundColor(.secondary.opacity(0.6))
                                    .onTapGesture {
                                        isEditingDescription = true
                                    }
                                    .onHover { hovering in
                                        if hovering {
                                            NSCursor.iBeam.push()
                                        } else {
                                            NSCursor.pop()
                                        }
                                    }
                            }
                        }
                        .frame(maxWidth: 200)
                    }
                }

                Spacer()

                if mode == .edit, onDelete != nil {
                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help("Delete rule")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 16)
            .onHover { hovering in
                isHoveringHeader = hovering
            }

            // Content
            ScrollView {
                VStack(spacing: spacing) {
                    // Start
                    keyInputField(
                        label: "Start",
                        key: $input,
                        isRecording: $isRecordingInput
                    )

                    // Finish
                    keyInputField(
                        label: "Finish",
                        key: $output,
                        isRecording: $isRecordingOutput
                    )

                    // Advanced options - using native Toggle for reveal
                    advancedSection

                    // Validation error
                    if let error = validationError {
                        Text(error)
                            .font(.callout)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(20)
            }

            Divider()

            // Footer buttons
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .frame(width: 460, height: showAdvanced ? 540 : 340)
        .animation(.easeInOut(duration: 0.25), value: showAdvanced)
        .background(Color(NSColor.windowBackgroundColor))
        .alert("Delete Rule?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let rule = existingRule {
                    onDelete?(rule)
                }
                dismiss()
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .sheet(isPresented: $showConflictDialog) {
            ConflictResolutionDialog(
                pendingConflict: pendingConflict,
                onChoice: { choice in
                    resolveConflict(choice)
                    showConflictDialog = false
                },
                onCancel: {
                    showConflictDialog = false
                }
            )
        }
        .onAppear {
            initializeFromBehavior()
            // Ensure Double Tap is shown when advanced is enabled
            if showAdvanced, tapDanceSteps.isEmpty {
                tapDanceSteps = defaultTapDanceSteps
            }
        }
    }

    // MARK: - Conflict Resolution

    private func resolveConflict(_ choice: BehaviorConflictChoice) {
        guard let conflict = pendingConflict else { return }

        switch choice {
        case .keepHold:
            // Clear all tap dance steps and keep hold
            for i in tapDanceSteps.indices {
                tapDanceSteps[i].action = ""
            }
            syncBehavior()

        case .keepTapDance:
            // Clear hold and keep tap dance
            holdAction = ""
            holdBehavior = .basic
            customTapKeysText = ""
            syncBehavior()

            // Now start recording in the attempted field
            switch conflict.attemptedField {
            case let .tapDance(index):
                if index < tapDanceSteps.count {
                    recordingTapDanceIndex = index
                    startKeyCapture(
                        into: Binding(
                            get: { tapDanceSteps[index].action },
                            set: { tapDanceSteps[index].action = $0; syncBehavior() }
                        ),
                        isRecording: Binding(
                            get: { recordingTapDanceIndex == index },
                            set: { if !$0 { recordingTapDanceIndex = nil } }
                        )
                    )
                }
            case .hold:
                break // This case shouldn't happen for keepTapDance
            }
        }

        // If keeping hold, start recording in hold field
        if case .keepHold = choice, case .hold = conflict.attemptedField {
            isRecordingHold = true
            startKeyCapture(into: $holdAction, isRecording: $isRecordingHold)
        }

        pendingConflict = nil
    }

    // MARK: - Clear Button Component

    private struct ClearButton: View {
        let action: () -> Void
        @State private var isHovered = false
        @State private var isPressed = false

        var body: some View {
            Button(action: {
                action()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    .scaleEffect(isPressed ? 0.9 : isHovered ? 1.1 : 1.0)
                    .opacity(isHovered ? 0.8 : 0.6)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Clear")
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            withAnimation(.easeInOut(duration: 0.1)) {
                                isPressed = true
                            }
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.easeInOut(duration: 0.1)) {
                            isPressed = false
                        }
                    }
            )
        }
    }

    // MARK: - Key Input Field

    @ViewBuilder
    private func keyInputField(
        label: String,
        key: Binding<String>,
        isRecording: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            // Label on left
            Text(label)
                .font(.body)
                .foregroundColor(.primary)
                .frame(width: 100, alignment: .leading)

            // Input field and button
            HStack(spacing: 12) {
                // Input field
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color(NSColor.controlBackgroundColor))

                    HStack {
                        if isRecording.wrappedValue {
                            Text("Press a key...")
                                .font(.body)
                                .foregroundColor(.secondary)
                        } else if key.wrappedValue.isEmpty {
                            Text("Click to record")
                                .font(.body)
                                .foregroundColor(.secondary.opacity(0.5))
                        } else {
                            Text(KeyDisplayName.display(for: key.wrappedValue))
                                .font(.body.weight(.semibold))
                                .foregroundColor(.primary)
                        }

                        Spacer()

                        // Clear button - visible in dark mode with subtle hover/click states
                        if !key.wrappedValue.isEmpty, !isRecording.wrappedValue {
                            ClearButton {
                                key.wrappedValue = ""
                                syncBehavior()
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: fieldHeight)
                .focusable(false)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            isRecording.wrappedValue ? Color.accentColor : Color.secondary.opacity(0.2),
                            lineWidth: isRecording.wrappedValue ? 2 : 1
                        )
                )
                .onTapGesture {
                    if !isRecording.wrappedValue, !anyOtherRecording(except: isRecording) {
                        isRecording.wrappedValue = true
                        startKeyCapture(into: key, isRecording: isRecording)
                    }
                }

                // Record button
                Button {
                    if isRecording.wrappedValue {
                        isRecording.wrappedValue = false
                    } else if !anyOtherRecording(except: isRecording) {
                        isRecording.wrappedValue = true
                        startKeyCapture(into: key, isRecording: isRecording)
                    }
                } label: {
                    Image(systemName: isRecording.wrappedValue ? "stop.fill" : "record.circle")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(width: buttonSize, height: buttonSize)
                        .background(
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(isRecording.wrappedValue ? Color.red : Color.accentColor)
                        )
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
    }

    private func anyOtherRecording(except current: Binding<Bool>) -> Bool {
        let allRecordings = [
            $isRecordingInput, $isRecordingOutput,
            $isRecordingHold
        ]
        let hasTapDanceRecording = recordingTapDanceIndex != nil
        return allRecordings.contains { $0.wrappedValue && $0.wrappedValue != current.wrappedValue } || hasTapDanceRecording
    }

    // MARK: - Advanced Section

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: spacing) {
            // Toggle with switch on left, label on right, left aligned
            HStack(spacing: 8) {
                Toggle("", isOn: $showAdvanced)
                    .toggleStyle(.switch)
                    .labelsHidden()

                Text("Hold, Double Tap, etc.")
                    .font(.body)
                    .foregroundColor(.primary)
                    .onTapGesture {
                        showAdvanced.toggle()
                    }

                Spacer()
            }
            .onChange(of: showAdvanced) { _, isExpanded in
                if isExpanded {
                    // Initialize with Double Tap by default (always shown)
                    if tapDanceSteps.isEmpty {
                        tapDanceSteps = defaultTapDanceSteps
                    }
                } else {
                    behavior = nil
                    holdAction = ""
                    tapDanceSteps = []
                    tappingTerm = 200
                    recordingTapDanceIndex = nil
                    holdBehavior = .basic
                    customTapKeysText = ""
                    showTimingAdvanced = false
                    tapTimeout = 200
                    holdTimeout = 200
                }
            }

            if showAdvanced {
                VStack(alignment: .leading, spacing: spacing) {
                    // Hold action with progressive disclosure
                    VStack(alignment: .leading, spacing: 8) {
                        actionField(
                            label: "On Hold",
                            key: $holdAction,
                            isRecording: $isRecordingHold,
                            onAttemptRecord: {
                                // Check for conflict before recording
                                if tapDanceSteps.contains(where: { !$0.action.isEmpty }) {
                                    pendingConflict = BehaviorConflict(
                                        attemptedField: .hold,
                                        existingHoldAction: holdAction,
                                        existingTapDanceActions: tapDanceSteps.map(\.action).filter { !$0.isEmpty }
                                    )
                                    showConflictDialog = true
                                    return false // Don't start recording
                                }
                                return true // OK to record
                            }
                        )
                        .onChange(of: holdAction) { _, _ in
                            syncBehavior()
                        }

                        // Hold behavior options - shown when hold action is set
                        if !holdAction.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Hold Behavior:")
                                    .font(.body.weight(.medium))
                                    .foregroundColor(.primary)

                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(HoldBehaviorType.allCases, id: \.self) { behaviorType in
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: 8) {
                                                Button {
                                                    holdBehavior = behaviorType
                                                    syncBehavior()
                                                } label: {
                                                    Image(systemName: holdBehavior == behaviorType ? "checkmark.circle.fill" : "circle")
                                                        .foregroundColor(holdBehavior == behaviorType ? .accentColor : .secondary)
                                                        .font(.body)
                                                }
                                                .buttonStyle(.plain)
                                                .focusable(false)

                                                Text(behaviorType.rawValue)
                                                    .font(.body)
                                                    .foregroundColor(.primary)
                                            }

                                            // Description for selected behavior
                                            if holdBehavior == behaviorType {
                                                Text(behaviorType.description)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                    .padding(.leading, 28)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                        }
                                    }
                                }

                                // Custom keys input (only shown for customKeys option)
                                if holdBehavior == .customKeys {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Keys that trigger early tap:")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        TextField("e.g., a s d f", text: $customTapKeysText)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 200)
                                            .onChange(of: customTapKeysText) { _, _ in
                                                syncBehavior()
                                            }
                                        Text("Space or comma separated. Press these keys to trigger tap instead of hold.")
                                            .font(.caption2)
                                            .foregroundColor(.secondary.opacity(0.7))
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(.leading, 28)
                                    .padding(.top, 4)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                            .padding(.leading, 112) // Align with input fields
                            .padding(.top, 4)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .animation(.easeInOut(duration: 0.2), value: holdAction.isEmpty)
                        }
                    }

                    // Tap Dance steps (dynamic list)
                    VStack(alignment: .leading, spacing: spacing) {
                        ForEach(Array(tapDanceSteps.indices), id: \.self) { index in
                            HStack(spacing: 8) {
                                actionField(
                                    label: tapDanceSteps[index].label,
                                    key: Binding(
                                        get: { tapDanceSteps[index].action },
                                        set: { newValue in
                                            tapDanceSteps[index].action = newValue
                                            syncBehavior()
                                        }
                                    ),
                                    isRecording: Binding(
                                        get: { recordingTapDanceIndex == index },
                                        set: { isRecording in
                                            if isRecording {
                                                recordingTapDanceIndex = index
                                            } else {
                                                recordingTapDanceIndex = nil
                                            }
                                        }
                                    ),
                                    onAttemptRecord: {
                                        // Check for conflict before recording
                                        if !holdAction.isEmpty {
                                            pendingConflict = BehaviorConflict(
                                                attemptedField: .tapDance(index: index),
                                                existingHoldAction: holdAction,
                                                existingTapDanceActions: tapDanceSteps.map(\.action).filter { !$0.isEmpty }
                                            )
                                            showConflictDialog = true
                                            return false // Don't start recording
                                        }
                                        return true // OK to record
                                    }
                                )
                                .onChange(of: tapDanceSteps[index].action) { _, _ in
                                    syncBehavior()
                                }

                                // Remove step button (only for Triple Tap and above, index > 0)
                                if index == 0 {
                                    // No remove for Double Tap (index 0)
                                    EmptyView()
                                } else {
                                    Button {
                                        tapDanceSteps.remove(at: index)
                                        syncBehavior()
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .font(.title3)
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .focusable(false)
                                }
                            }
                        }

                        // Add step button (Triple Tap, Quad Tap, etc.)
                        Button {
                            let nextIndex = tapDanceSteps.count
                            let label = nextIndex < tapDanceStepLabels.count
                                ? tapDanceStepLabels[nextIndex]
                                : "\(nextIndex + 2) Taps"
                            tapDanceSteps.append((label: label, action: ""))
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle")
                                    .foregroundColor(.accentColor)
                                Text("Add Triple Tap, etc.")
                                    .foregroundColor(.primary)
                            }
                            .font(.body)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .padding(.leading, 112) // Align with input fields
                    }

                    // Timing with progressive disclosure
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Text("Timing (ms)")
                                .font(.body)
                                .foregroundColor(.primary)
                                .frame(width: 100, alignment: .leading)

                            Group {
                                if showTimingAdvanced {
                                    // Separate tap and hold timeouts
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Separate timeouts:")
                                            .font(.caption)
                                            .foregroundColor(.secondary)

                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack(spacing: 12) {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text("Tap window")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                    TextField("200", value: $tapTimeout, format: .number)
                                                        .textFieldStyle(.roundedBorder)
                                                        .frame(width: 80)
                                                        .focusable(false)
                                                        .onChange(of: tapTimeout) { _, _ in syncBehavior() }
                                                        .onHover { hovering in
                                                            if hovering {
                                                                NSCursor.iBeam.push()
                                                            } else {
                                                                NSCursor.pop()
                                                            }
                                                        }
                                                }

                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text("Hold delay")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                    TextField("200", value: $holdTimeout, format: .number)
                                                        .textFieldStyle(.roundedBorder)
                                                        .frame(width: 80)
                                                        .focusable(false)
                                                        .onChange(of: holdTimeout) { _, _ in syncBehavior() }
                                                        .onHover { hovering in
                                                            if hovering {
                                                                NSCursor.iBeam.push()
                                                            } else {
                                                                NSCursor.pop()
                                                            }
                                                        }
                                                }
                                            }

                                            Text("Tap window: time before tap becomes hold. Hold delay: time before hold activates.")
                                                .font(.caption2)
                                                .foregroundColor(.secondary.opacity(0.7))
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                } else {
                                    // Single timing value (default)
                                    TextField("200", value: $tappingTerm, format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 80)
                                        .focusable(false)
                                        .onChange(of: tappingTerm) { _, _ in
                                            // Sync both timeouts when single value changes
                                            tapTimeout = tappingTerm
                                            holdTimeout = tappingTerm
                                            syncBehavior()
                                        }
                                        .onHover { hovering in
                                            if hovering {
                                                NSCursor.iBeam.push()
                                            } else {
                                                NSCursor.pop()
                                            }
                                        }
                                }
                            }
                            .animation(.easeInOut(duration: 0.2), value: showTimingAdvanced)

                            // Gear icon for advanced timing options
                            Button {
                                showTimingAdvanced.toggle()
                                if showTimingAdvanced {
                                    // Initialize separate values from single value
                                    tapTimeout = tappingTerm
                                    holdTimeout = tappingTerm
                                } else {
                                    // Sync single value from tapTimeout (or average?)
                                    tappingTerm = tapTimeout
                                }
                                syncBehavior()
                            } label: {
                                Image(systemName: "gearshape")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                            .help("Advanced timing options")

                            Spacer()

                            // Reset button
                            Button("Reset") {
                                resetAdvanced()
                            }
                            .buttonStyle(.bordered)
                            .focusable(false)
                        }
                    }
                }
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private func actionField(
        label: String,
        key: Binding<String>,
        isRecording: Binding<Bool>,
        onAttemptRecord: (() -> Bool)? = nil // Returns true if OK to record, false to block
    ) -> some View {
        HStack(spacing: 12) {
            // Label on left
            Text(label)
                .font(.body)
                .foregroundColor(.primary)
                .frame(width: 100, alignment: .leading)

            // Input field
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(NSColor.controlBackgroundColor))

                HStack {
                    if isRecording.wrappedValue {
                        Text("Press a key...")
                            .font(.body)
                            .foregroundColor(.secondary)
                    } else if key.wrappedValue.isEmpty {
                        Text("Optional")
                            .font(.body)
                            .foregroundColor(.secondary.opacity(0.4))
                    } else {
                        Text(KeyDisplayName.display(for: key.wrappedValue))
                            .font(.body.weight(.semibold))
                            .foregroundColor(.primary)
                    }

                    Spacer()

                    // Clear button
                    if !key.wrappedValue.isEmpty, !isRecording.wrappedValue {
                        ClearButton {
                            key.wrappedValue = ""
                            syncBehavior()
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: fieldHeight)
            .focusable(false)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        isRecording.wrappedValue ? Color.accentColor : Color.secondary.opacity(0.2),
                        lineWidth: isRecording.wrappedValue ? 2 : 1
                    )
            )
            .onTapGesture {
                if !isRecording.wrappedValue, !anyOtherRecording(except: isRecording) {
                    // Check if we should show conflict dialog
                    if let check = onAttemptRecord, !check() {
                        return // Blocked by conflict
                    }
                    isRecording.wrappedValue = true
                    startKeyCapture(into: key, isRecording: isRecording)
                }
            }

            // Record button
            Button {
                if isRecording.wrappedValue {
                    isRecording.wrappedValue = false
                } else if !anyOtherRecording(except: isRecording) {
                    // Check if we should show conflict dialog
                    if let check = onAttemptRecord, !check() {
                        return // Blocked by conflict
                    }
                    isRecording.wrappedValue = true
                    startKeyCapture(into: key, isRecording: isRecording)
                }
            } label: {
                Image(systemName: isRecording.wrappedValue ? "stop.fill" : "record.circle")
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(width: buttonSize, height: buttonSize)
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(isRecording.wrappedValue ? Color.red : Color.accentColor)
                    )
            }
            .buttonStyle(.plain)
            .focusable(false)
        }
    }

    private func resetAdvanced() {
        holdAction = ""
        tapDanceSteps = defaultTapDanceSteps // Keep Double Tap, just clear it
        tappingTerm = 200
        recordingTapDanceIndex = nil
        holdBehavior = .basic
        customTapKeysText = ""
        showTimingAdvanced = false
        tapTimeout = 200
        holdTimeout = 200
        syncBehavior()
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .focusable(false)

            Spacer()

            Button(mode == .create ? "Add" : "Save") {
                saveRule()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .focusable(false)
            .disabled(!canSave)
        }
    }

    // MARK: - Key Capture

    private func startKeyCapture(into key: Binding<String>, isRecording: Binding<Bool>) {
        var monitor: Any?
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape cancels recording
            if event.keyCode == 53 {
                isRecording.wrappedValue = false
                if let m = monitor {
                    NSEvent.removeMonitor(m)
                }
                return nil
            }

            let keyName = Self.keyNameFromEvent(event)
            key.wrappedValue = keyName
            isRecording.wrappedValue = false
            syncBehavior()
            if let m = monitor {
                NSEvent.removeMonitor(m)
            }
            return nil
        }

        // Timeout after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            if isRecording.wrappedValue {
                isRecording.wrappedValue = false
                if let m = monitor { NSEvent.removeMonitor(m) }
            }
        }
    }

    private static func keyNameFromEvent(_ event: NSEvent) -> String {
        let keyCode = event.keyCode
        let modifiers = event.modifierFlags

        var prefix = ""
        if modifiers.contains(.command) { prefix += "M-" }
        if modifiers.contains(.control) { prefix += "C-" }
        if modifiers.contains(.option) { prefix += "A-" }
        if modifiers.contains(.shift) { prefix += "S-" }

        let keyName = switch keyCode {
        case 0: "a"
        case 1: "s"
        case 2: "d"
        case 3: "f"
        case 4: "h"
        case 5: "g"
        case 6: "z"
        case 7: "x"
        case 8: "c"
        case 9: "v"
        case 11: "b"
        case 12: "q"
        case 13: "w"
        case 14: "e"
        case 15: "r"
        case 16: "y"
        case 17: "t"
        case 18: "1"
        case 19: "2"
        case 20: "3"
        case 21: "4"
        case 22: "6"
        case 23: "5"
        case 24: "="
        case 25: "9"
        case 26: "7"
        case 27: "-"
        case 28: "8"
        case 29: "0"
        case 30: "]"
        case 31: "o"
        case 32: "u"
        case 33: "["
        case 34: "i"
        case 35: "p"
        case 36: "ret"
        case 37: "l"
        case 38: "j"
        case 39: "'"
        case 40: "k"
        case 41: ";"
        case 42: "\\"
        case 43: ","
        case 44: "/"
        case 45: "n"
        case 46: "m"
        case 47: "."
        case 48: "tab"
        case 49: "spc"
        case 50: "`"
        case 51: "bspc"
        case 53: "esc"
        case 55: "lmet"
        case 56: "lsft"
        case 57: "caps"
        case 58: "lalt"
        case 59: "lctl"
        case 60: "rsft"
        case 61: "ralt"
        case 62: "rctl"
        case 63: "fn"
        case 96: "f5"
        case 97: "f6"
        case 98: "f7"
        case 99: "f3"
        case 100: "f8"
        case 101: "f9"
        case 103: "f11"
        case 105: "f13"
        case 107: "f14"
        case 109: "f10"
        case 111: "f12"
        case 113: "f15"
        case 118: "f4"
        case 119: "end"
        case 120: "f2"
        case 121: "pgdn"
        case 122: "f1"
        case 123: "left"
        case 124: "right"
        case 125: "down"
        case 126: "up"
        default: "k\(keyCode)"
        }

        return prefix + keyName
    }

    // MARK: - Behavior Sync

    private func initializeFromBehavior() {
        guard let behavior else {
            // No existing behavior - ensure Double Tap is shown by default
            if showAdvanced, tapDanceSteps.isEmpty {
                tapDanceSteps = defaultTapDanceSteps
            }
            return
        }

        switch behavior {
        case let .dualRole(dr):
            holdAction = dr.holdAction
            tappingTerm = dr.tapTimeout
            tapTimeout = dr.tapTimeout
            holdTimeout = dr.holdTimeout

            // Determine hold behavior type from flags
            if !dr.customTapKeys.isEmpty {
                holdBehavior = .customKeys
                customTapKeysText = dr.customTapKeys.joined(separator: " ")
            } else if dr.activateHoldOnOtherKey {
                holdBehavior = .triggerEarly
            } else if dr.quickTap {
                holdBehavior = .quickTap
            } else {
                holdBehavior = .basic
            }

            // Show advanced timing options if they differ
            if dr.tapTimeout != dr.holdTimeout {
                showTimingAdvanced = true
            }

            // Ensure Double Tap entry is available (empty) even for dualRole
            if tapDanceSteps.isEmpty {
                tapDanceSteps = defaultTapDanceSteps
            }

        case let .tapDance(td):
            tappingTerm = td.windowMs
            tapTimeout = td.windowMs
            holdTimeout = td.windowMs
            // Skip index 0 (single tap = output), load the rest as tap-dance steps
            tapDanceSteps = []
            for (index, step) in td.steps.enumerated() {
                if index == 0 {
                    continue // Single tap = output (handled by Finish field)
                }
                let label = index <= tapDanceStepLabels.count
                    ? tapDanceStepLabels[index - 1]
                    : "\(index + 1) Taps"
                tapDanceSteps.append((label: label, action: step.action))
            }
            // Ensure at least Double Tap exists
            if tapDanceSteps.isEmpty {
                tapDanceSteps = defaultTapDanceSteps
            }
        }
    }

    private func syncBehavior() {
        guard showAdvanced else {
            behavior = nil
            return
        }

        // Check if any advanced actions are set
        let hasHold = !holdAction.isEmpty
        let hasTapDanceSteps = tapDanceSteps.contains { !$0.action.isEmpty }

        if !hasHold, !hasTapDanceSteps {
            behavior = nil
            return
        }

        // IMPORTANT: Kanata's tap-dance doesn't support hold detection - it only counts taps.
        // If hold is set, we MUST use tap-hold (dual-role) even if tap-dance steps are also set.
        // Kanata cannot detect both hold and tap-count on the same key.
        // The UI prevents both from being set simultaneously, but we prioritize hold if somehow both are set.
        if hasHold {
            // Use dual-role for hold detection (tap = output, hold = holdAction)
            // Use separate timeouts if advanced timing is enabled, otherwise use single value
            let tapTimeoutValue = showTimingAdvanced ? tapTimeout : tappingTerm
            let holdTimeoutValue = showTimingAdvanced ? holdTimeout : tappingTerm

            // Parse custom tap keys from text field
            let customKeys: [String] = if holdBehavior == .customKeys {
                customTapKeysText
                    .replacingOccurrences(of: ",", with: " ")
                    .split(separator: " ")
                    .map { String($0).trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            } else {
                []
            }

            behavior = .dualRole(DualRoleBehavior(
                tapAction: output,
                holdAction: holdAction,
                tapTimeout: tapTimeoutValue,
                holdTimeout: holdTimeoutValue,
                activateHoldOnOtherKey: holdBehavior.activateHoldOnOtherKey,
                quickTap: holdBehavior.quickTapMode,
                customTapKeys: customKeys
            ))
            return
        }

        // If no hold, use tap-dance for tap-count based behaviors
        let hasTap = !output.isEmpty
        if hasTap || hasTapDanceSteps {
            var steps: [TapDanceStep] = []
            // Always include single tap (from output field)
            if hasTap {
                steps.append(TapDanceStep(label: "Single tap", action: output))
            }
            // Add all configured tap-dance steps
            for step in tapDanceSteps where !step.action.isEmpty {
                steps.append(TapDanceStep(label: step.label, action: step.action))
            }

            if !steps.isEmpty {
                behavior = .tapDance(TapDanceBehavior(
                    windowMs: tappingTerm,
                    steps: steps
                ))
            } else {
                behavior = nil
            }
        } else {
            behavior = nil
        }
    }

    // MARK: - Save

    private func saveRule() {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedInput.isEmpty {
            validationError = "Input key required"
            return
        }
        if trimmedOutput.isEmpty {
            validationError = "Output key required"
            return
        }

        syncBehavior()

        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let rule = CustomRule(
            id: existingRule?.id ?? UUID(),
            title: customName,
            input: trimmedInput,
            output: trimmedOutput,
            isEnabled: isEnabled,
            notes: trimmedDescription.isEmpty ? nil : trimmedDescription,
            createdAt: existingRule?.createdAt ?? Date(),
            behavior: behavior
        )

        let errors = CustomRuleValidator.validate(rule, existingRules: existingRules)
        if let firstError = errors.first {
            switch firstError {
            case let .invalidInputKey(key):
                validationError = "Invalid input key: \(key)"
            case let .invalidOutputKey(key):
                validationError = "Invalid output key: \(key)"
            case .selfMapping:
                validationError = "Input and output are the same"
            case let .conflict(name, _):
                validationError = "Conflicts with '\(name)'"
            case .emptyInput, .emptyOutput:
                validationError = "Keys cannot be empty"
            }
            return
        }

        onSave(rule)
        dismiss()
    }
}

// MARK: - Preview

#Preview("Create") {
    CustomRuleEditorView(
        rule: nil,
        existingRules: [],
        onSave: { _ in },
        onDelete: nil
    )
}

#Preview("Edit") {
    CustomRuleEditorView(
        rule: CustomRule(
            id: UUID(),
            title: "Caps to Escape",
            input: "caps",
            output: "esc",
            isEnabled: true,
            notes: nil,
            createdAt: Date(),
            behavior: nil
        ),
        existingRules: [],
        onSave: { _ in },
        onDelete: { _ in }
    )
}

#Preview("With Behavior") {
    CustomRuleEditorView(
        rule: CustomRule(
            id: UUID(),
            title: "",
            input: "caps",
            output: "esc",
            isEnabled: true,
            notes: nil,
            createdAt: Date(),
            behavior: .dualRole(DualRoleBehavior(
                tapAction: "esc",
                holdAction: "lctl",
                tapTimeout: 200,
                holdTimeout: 200,
                activateHoldOnOtherKey: false,
                quickTap: false
            ))
        ),
        existingRules: [],
        onSave: { _ in },
        onDelete: { _ in }
    )
}
