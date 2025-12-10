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
    @State private var recordingState = RecordingStateTracker()
    @State private var validationError: String?
    @State private var ruleValidationErrors: [CustomRuleValidator.ValidationError] = []
    @State private var showValidationAlert = false
    @State private var showDeleteConfirmation = false
    @State private var description: String = ""
    @State private var isEditingDescription: Bool = false
    @State private var isHoveringHeader: Bool = false

    // Advanced action states
    @State private var holdAction: String = ""
    @State private var tapDanceSteps: [(label: String, action: String)] = []
    @State private var tappingTerm: Int = 200
    @State private var recordingTapDanceIndex: Int?
    @State private var keyboardCapture: KeyboardCapture?
    @State private var sequenceFinalizeTimer: Timer?

    // Conflict dialog state
    @State private var showConflictDialog: Bool = false
    @State private var pendingConflict: BehaviorConflict?

    // Standalone mode controls state
    @State private var systemHasProblems: Bool = false
    @EnvironmentObject private var kanataManager: KanataViewModel

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

    enum RecordingField: Equatable {
        case input
        case output
        case hold
        case tapDance(index: Int)
    }

    struct RecordingStateTracker {
        private(set) var active: RecordingField?
        private(set) var isInput = false
        private(set) var isOutput = false
        private(set) var isHold = false

        mutating func begin(_ field: RecordingField) {
            cancel()
            active = field
            switch field {
            case .input: isInput = true
            case .output: isOutput = true
            case .hold: isHold = true
            case .tapDance: break // handled separately by index in view state
            }
        }

        mutating func cancel() {
            active = nil
            isInput = false
            isOutput = false
            isHold = false
        }

        func isRecording(_ field: RecordingField, tapDanceIndex: Int?) -> Bool {
            switch field {
            case .input: isInput
            case .output: isOutput
            case .hold: isHold
            case let .tapDance(index): tapDanceIndex == index
            }
        }
    }

    private var tapDanceStepLabels: [String] {
        ["Double Tap", "Triple Tap", "Quad Tap", "Quint Tap", "Sext Tap", "Sept Tap", "Oct Tap"]
    }

    /// Label for the "Add next tap step" button - shows what will be added next
    private var nextTapStepLabel: String {
        let nextIndex = tapDanceSteps.count
        if nextIndex < tapDanceStepLabels.count {
            return "Add \(tapDanceStepLabels[nextIndex])"
        } else {
            return "Add \(nextIndex + 2) Taps"
        }
    }

    /// Default tap dance steps with only Double Tap
    private var defaultTapDanceSteps: [(label: String, action: String)] {
        [(label: "Double Tap", action: "")]
    }

    private let existingRule: CustomRule?
    private let existingRules: [CustomRule]
    private let mode: Mode
    private let isStandalone: Bool // When true, acts as home screen (no close button, resets after save)
    let onSave: (CustomRule) -> Void
    let onDelete: ((CustomRule) -> Void)?
    let onShowWizard: (() -> Void)?
    @State private var autoSaveTimer: Timer?

    // Toast state
    @State private var showToast: Bool = false
    @State private var toastMessage: String = ""
    @State private var toastIsError: Bool = false

    // Consistent sizing
    private let fieldHeight: CGFloat = 44
    private let buttonSize: CGFloat = 44
    private let cornerRadius: CGFloat = 8
    private let spacing: CGFloat = 16

    init(
        rule: CustomRule?,
        existingRules: [CustomRule] = [],
        isStandalone: Bool = false,
        onSave: @escaping (CustomRule) -> Void,
        onDelete: ((CustomRule) -> Void)? = nil,
        onShowWizard: (() -> Void)? = nil
    ) {
        existingRule = rule
        self.existingRules = existingRules
        self.isStandalone = isStandalone
        self.onSave = onSave
        self.onDelete = onDelete
        self.onShowWizard = onShowWizard
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
            let inputDisplay = input.isEmpty ? "?" : displayLabel(for: input)
            let outputDisplay = output.isEmpty ? "?" : displayLabel(for: output)
            return "\(inputDisplay) → \(outputDisplay)"
        } else {
            return "New Rule"
        }
    }

    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedOutput: String {
        output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasRequiredFields: Bool {
        !trimmedInput.isEmpty && !trimmedOutput.isEmpty
    }

    private var isRuleValid: Bool {
        hasRequiredFields && ruleValidationErrors.isEmpty
    }

    /// Number of active (enabled) custom rules - used for the indicator at the bottom
    private var activeRulesCount: Int {
        kanataManager.customRules.filter(\.isEnabled).count
    }

    /// Compute the ideal height based on content
    private var idealHeight: CGFloat {
        // Chrome: header (44) + scroll content padding (32 top+bottom) + bottom safe area (16)
        let chrome: CGFloat = 92
        var total = chrome + keycapRegionHeight

        // Controls row (Hold/Double Tap toggle + Pause button) - always visible
        // Button height (~24) + vertical padding (16 top + 20 bottom for breathing room)
        let controlsRowHeight: CGFloat = 60

        if showAdvanced {
            let holdHeight: CGFloat = holdAction.isEmpty ? 60 : 140
            let tapDanceHeight = CGFloat(max(tapDanceSteps.count, 1)) * 78
            let timingHeight: CGFloat = showTimingAdvanced ? 100 : 60
            let addResetHeight: CGFloat = 44 // add step + reset row
            total += controlsRowHeight + holdHeight + tapDanceHeight + timingHeight + addResetHeight
        } else {
            total += controlsRowHeight
        }

        // Cap to avoid runaway height but allow plenty of room for long sequences
        return min(total, 760)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Controls bar for standalone mode (below titlebar)
            if isStandalone {
                standaloneControlsBar
            }

            // Content - scrolls only when needed
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        // Input/Output keycap pair (R2 style)
                        keycapPairSection
                            .padding(.bottom, 16)

                        // Advanced options - positioned directly below keycaps
                        advancedSection

                        // Validation error
                        if let error = validationError {
                            Text(error)
                                .font(.callout)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 12)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    // In standalone mode, center content vertically until it needs to scroll
                    .frame(minHeight: isStandalone ? geometry.size.height : 0, alignment: .center)
                }
            }
        }
        .frame(width: isStandalone ? nil : 460, height: isStandalone ? nil : idealHeight)
        .frame(maxWidth: isStandalone ? .infinity : nil, maxHeight: isStandalone ? .infinity : nil)
        .preference(key: WindowHeightPreferenceKey.self, value: isStandalone ? idealHeight : 0)
        .animation(.easeInOut(duration: 0.25), value: showAdvanced)
        .animation(.easeInOut(duration: 0.25), value: tapDanceSteps.count)
        .background(isStandalone ? Color.clear : Color(NSColor.windowBackgroundColor))
        .safeAreaInset(edge: .top, spacing: 0) {
            // In standalone mode, header is in the native titlebar accessory
            // In sheet mode, show the SwiftUI header
            if !isStandalone {
                sheetHeader
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ResetRuleEditorForm"))) { _ in
            resetForm()
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                if showToast {
                    HStack(spacing: 6) {
                        Image(systemName: toastIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(toastIsError ? .red : .green)
                            .font(.system(size: 14))
                        Text(toastMessage)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Active rules indicator - shown when there are enabled rules (standalone mode only)
                if isStandalone, activeRulesCount > 0 {
                    Text("\(activeRulesCount) active rule\(activeRulesCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .onTapGesture {
                            openRulesSettings()
                        }
                        .onHover { hovering in
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                }
            }
            .padding(.bottom, 12)
            .animation(.easeInOut(duration: 0.3), value: activeRulesCount)
        }
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
        .alert("Invalid Rule", isPresented: $showValidationAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationError ?? "Please fix the highlighted fields.")
        }
        .onAppear {
            initializeFromBehavior()
            // Ensure Double Tap is shown when advanced is enabled
            if showAdvanced, tapDanceSteps.isEmpty {
                tapDanceSteps = defaultTapDanceSteps
            }
            refreshValidation()
        }
        .onDisappear {
            cancelActiveRecording()
            autoSaveTimer?.invalidate()
        }
        .focusEffectDisabled()
        .onChange(of: input) { _, _ in
            refreshValidation()
            scheduleAutoSave()
        }
        .onChange(of: output) { _, _ in
            refreshValidation()
            scheduleAutoSave()
        }
    }

    /// Schedule auto-save after a short debounce when both input and output are filled
    private func scheduleAutoSave() {
        // Cancel previous timer
        autoSaveTimer?.invalidate()

        // Only auto-save if both fields are filled and valid
        guard hasRequiredFields else { return }

        // Debounce: wait 600ms after last change before saving
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { _ in
            Task { @MainActor in
                autoSaveIfValid()
            }
        }
    }

    /// Auto-save the rule if it's valid (no user confirmation needed)
    private func autoSaveIfValid() {
        syncBehavior()
        let rule = buildRuleForValidation()
        let errors = CustomRuleValidator.validate(rule, existingRules: existingRules)
        ruleValidationErrors = errors

        // Only auto-save if there are no validation errors
        guard errors.isEmpty else {
            // Build detailed error message for modal
            let errorDetails = errors.map { error -> String in
                switch error {
                case .invalidInputKey(let key):
                    return "Invalid input key: '\(key)'\n\nValid keys include: a-z, 0-9, caps, esc, tab, ret, spc, bspc, del, lmet, rmet, lctl, rctl, lsft, rsft, lalt, ralt, f1-f20, arrow keys, etc.\n\nTip: Use the Record button to capture keys instead of typing them."
                case .invalidOutputKey(let key):
                    return "Invalid output key: '\(key)'\n\nValid keys include: a-z, 0-9, caps, esc, tab, ret, spc, bspc, del, lmet, rmet, lctl, rctl, lsft, rsft, lalt, ralt, f1-f20, arrow keys, etc.\n\nTip: Use the Record button to capture keys instead of typing them."
                default:
                    return error.errorDescription ?? "Unknown validation error"
                }
            }.joined(separator: "\n\n")

            validationError = errorDetails
            showValidationAlert = true
            return
        }

        // Clear any previous error and save
        validationError = nil
        onSave(rule)
        showToast(message: "Saved", isError: false)

        // In standalone mode, reset form after save so user can create another rule
        if isStandalone {
            // Delay reset slightly so user sees the "Saved" toast
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(800))
                resetForm()
            }
        }
        // In sheet mode, don't dismiss - let user continue editing or close manually
    }

    /// Show a brief toast notification
    private func showToast(message: String, isError: Bool) {
        toastMessage = message
        toastIsError = isError
        withAnimation(.easeInOut(duration: 0.2)) {
            showToast = true
        }

        // Auto-hide after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + (isError ? 2.5 : 1.5)) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showToast = false
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
                    beginRecording(
                        for: .tapDance(index: index),
                        key: Binding(
                            get: { tapDanceSteps[index].action },
                            set: { tapDanceSteps[index].action = $0; syncBehavior() }
                        )
                    )
                }
            case .hold:
                break // This case shouldn't happen for keepTapDance
            }
        }

        // If keeping hold, start recording in hold field
        if case .keepHold = choice, case .hold = conflict.attemptedField {
            beginRecording(for: .hold, key: $holdAction)
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
                    .foregroundStyle(Color(NSColor.tertiaryLabelColor))
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

    // MARK: - Keycap Pair Section (responsive, Mapper-style)

    private var keycapPairSection: some View {
        let windowWidth: CGFloat = 460
        let horizontalPadding: CGFloat = 24
        let contentWidth = windowWidth - horizontalPadding * 2
        let horizontalKeycapMaxWidth = (contentWidth - 60) / 2 // room for arrow + gaps
        let shouldStack = shouldStackKeycaps(
            inputLabel: inputDisplayLabel,
            outputLabel: outputDisplayLabel,
            maxWidth: horizontalKeycapMaxWidth
        )

        return VStack(spacing: shouldStack ? 14 : 18) {
            if shouldStack {
                VStack(spacing: 10) {
                    keycapColumn(
                        label: "Input",
                        isRecording: recordingState.isInput,
                        text: inputDisplayLabel,
                        maxWidth: contentWidth,
                        onTap: { toggleRecording(for: .input, binding: $input) },
                        onClear: input.isEmpty ? nil : {
                            input = ""
                            syncBehavior()
                            refreshValidation()
                        }
                    )

                    Image(systemName: "arrow.down")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    keycapColumn(
                        label: "Output",
                        isRecording: recordingState.isOutput,
                        text: outputDisplayLabel,
                        maxWidth: contentWidth,
                        onTap: { toggleRecording(for: .output, binding: $output) },
                        onClear: output.isEmpty ? nil : {
                            output = ""
                            syncBehavior()
                            refreshValidation()
                        }
                    )
                }
            } else {
                HStack(spacing: 18) {
                    keycapColumn(
                        label: "Input",
                        isRecording: recordingState.isInput,
                        text: inputDisplayLabel,
                        maxWidth: horizontalKeycapMaxWidth,
                        onTap: { toggleRecording(for: .input, binding: $input) },
                        onClear: input.isEmpty ? nil : { input = ""; syncBehavior() }
                    )

                    Image(systemName: "arrow.right")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    keycapColumn(
                        label: "Output",
                        isRecording: recordingState.isOutput,
                        text: outputDisplayLabel,
                        maxWidth: horizontalKeycapMaxWidth,
                        onTap: { toggleRecording(for: .output, binding: $output) },
                        onClear: output.isEmpty ? nil : { output = ""; syncBehavior() }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func keycapColumn(
        label: String,
        isRecording: Bool,
        text: String,
        maxWidth: CGFloat,
        onTap: @escaping () -> Void,
        onClear: (() -> Void)?
    ) -> some View {
        // Hide label once user has entered content (text is not placeholder "?")
        let hasContent = text != "?"

        VStack(spacing: 8) {
            ResponsiveKeycapView(
                label: text,
                isRecording: isRecording,
                maxWidth: maxWidth,
                onTap: onTap,
                onClear: onClear
            )
            // Keep label space reserved to prevent layout shift
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .opacity(hasContent ? 0 : 1)
        }
    }

    private func shouldStackKeycaps(inputLabel: String, outputLabel: String, maxWidth: CGFloat) -> Bool {
        // Heuristic: stack when either label would exceed available width at base size
        let baseFont: CGFloat = 26
        let padding: CGFloat = 20
        let available = maxWidth - padding * 2
        func needsWrap(_ text: String) -> Bool {
            let estimatedWidth = CGFloat(text.count) * baseFont * 0.6
            return estimatedWidth > available
        }
        return needsWrap(inputLabel) || needsWrap(outputLabel)
    }

    /// Estimated height for current keycap content to grow window height accordingly.
    private var keycapRegionHeight: CGFloat {
        // Match layout assumption of window width 460 with padding used above
        let windowWidth: CGFloat = 460
        let contentWidth = windowWidth - 24 * 2
        let horizontalKeycapMaxWidth = (contentWidth - 60) / 2
        let stack = shouldStackKeycaps(
            inputLabel: inputDisplayLabel,
            outputLabel: outputDisplayLabel,
            maxWidth: horizontalKeycapMaxWidth
        )

        let inputHeight = ResponsiveKeycapView.estimatedHeight(
            label: inputDisplayLabel,
            maxWidth: stack ? contentWidth : horizontalKeycapMaxWidth
        )
        let outputHeight = ResponsiveKeycapView.estimatedHeight(
            label: outputDisplayLabel,
            maxWidth: stack ? contentWidth : horizontalKeycapMaxWidth
        )

        // Labels always reserve space (hidden via opacity, not removed)
        // Caption label height + spacing
        let labelAndArrowPadding: CGFloat = stack ? 36 : 32

        if stack {
            return inputHeight + outputHeight + labelAndArrowPadding
        } else {
            return max(inputHeight, outputHeight) + labelAndArrowPadding
        }
    }

    private var inputDisplayLabel: String {
        input.isEmpty ? "?" : displayLabel(for: input)
    }

    private var outputDisplayLabel: String {
        output.isEmpty ? "?" : displayLabel(for: output)
    }

    private func cancelActiveRecording() {
        keyboardCapture?.stopCapture()
        sequenceFinalizeTimer?.invalidate()

        recordingState.cancel()
        recordingTapDanceIndex = nil
    }

    private func beginRecording(for field: RecordingField, key: Binding<String>) {
        cancelActiveRecording()

        recordingState.begin(field)
        if case let .tapDance(index) = field {
            recordingTapDanceIndex = index
        }

        startKeyCapture(into: key, field: field)
    }

    private func isRecording(_ field: RecordingField) -> Bool {
        recordingState.isRecording(field, tapDanceIndex: recordingTapDanceIndex)
    }

    private func toggleRecording(for field: RecordingField, binding: Binding<String>) {
        if recordingState.active == field {
            cancelActiveRecording()
        } else {
            beginRecording(for: field, key: binding)
        }
    }

    // MARK: - Advanced Section

    private var advancedSection: some View {
        VStack(spacing: 12) {
            // Compact action buttons - centered below keycaps with breathing room
            HStack(spacing: 20) {
                // Hold/Double Tap toggle
                Button {
                    showAdvanced.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: showAdvanced ? "minus.circle.fill" : "plus.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(showAdvanced ? Color.secondary : Color.blue)
                        Text("Hold / Double Tap")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .onChange(of: showAdvanced) { _, isExpanded in
                if isExpanded {
                    // Initialize with Double Tap by default (always shown)
                    if tapDanceSteps.isEmpty {
                        tapDanceSteps = defaultTapDanceSteps
                    }
                } else {
                    cancelActiveRecording()
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
                // Align under Input keycap: window 460, padding 40, center layout
                // Input keycap left edge is ~96pt from content edge, keycap is 80pt
                // For 60pt keycaps, offset by (80-60)/2 = 10pt to center under Input
                let advancedLeftPadding: CGFloat = 106

                VStack(alignment: .leading, spacing: spacing + 4) {
                    // Hold action with progressive disclosure
                    VStack(alignment: .leading, spacing: 8) {
                        actionField(
                            label: "On Hold",
                            key: $holdAction,
                            field: .hold,
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
                                    .foregroundStyle(.primary)

                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(HoldBehaviorType.allCases, id: \.self) { behaviorType in
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: 8) {
                                                Button {
                                                    holdBehavior = behaviorType
                                                    syncBehavior()
                                                } label: {
                                                    Image(systemName: holdBehavior == behaviorType ? "checkmark.circle.fill" : "circle")
                                                        .foregroundStyle(holdBehavior == behaviorType ? .accentColor : Color.secondary)
                                                        .font(.body)
                                                }
                                                .buttonStyle(.plain)
                                                .focusable(false)

                                                Text(behaviorType.rawValue)
                                                    .font(.body)
                                                    .foregroundStyle(.primary)
                                            }

                                            // Description for selected behavior
                                            if holdBehavior == behaviorType {
                                                Text(behaviorType.description)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
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
                                            .foregroundStyle(.secondary)
                                        TextField("e.g., a s d f", text: $customTapKeysText)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 200)
                                            .onChange(of: customTapKeysText) { _, _ in
                                                syncBehavior()
                                            }
                                        Text("Space or comma separated. Press these keys to trigger tap instead of hold.")
                                            .font(.caption2)
                                            .foregroundStyle(Color.secondary.opacity(0.7))
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(.leading, 28)
                                    .padding(.top, 4)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                            .padding(.leading, 76) // Offset from keycap for sub-options
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
                                    field: .tapDance(index: index),
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
                                        Image(systemName: "minus.circle")
                                            .font(.title3)
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .focusable(false)
                                    .accessibilityLabel("Remove tap step")
                                }
                            }
                        }

                        // Add step button (Triple Tap, Quad Tap, etc.) - subtle style
                        Button {
                            let nextIndex = tapDanceSteps.count
                            let label = nextIndex < tapDanceStepLabels.count
                                ? tapDanceStepLabels[nextIndex]
                                : "\(nextIndex + 2) Taps"
                            tapDanceSteps.append((label: label, action: ""))
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.blue)
                                Text(nextTapStepLabel)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    }

                    // Timing with progressive disclosure
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Text("Timing (ms)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(width: 80, alignment: .leading)

                            Group {
                                if showTimingAdvanced {
                                    // Separate tap and hold timeouts
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Separate timeouts:")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack(spacing: 12) {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text("Tap window")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
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
                                                        .foregroundStyle(.secondary)
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
                                                .foregroundStyle(Color.secondary.opacity(0.7))
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
                                    .foregroundStyle(.secondary)
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
                .padding(.leading, advancedLeftPadding)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private func actionField(
        label: String,
        key: Binding<String>,
        field: RecordingField,
        onAttemptRecord: (() -> Bool)? = nil // Returns true if OK to record, false to block
    ) -> some View {
        HStack(spacing: 16) {
            // Keycap-style input
            EditorKeycapView(
                label: key.wrappedValue.isEmpty ? "?" : displayLabel(for: key.wrappedValue),
                isRecording: isRecording(field),
                isEmpty: key.wrappedValue.isEmpty,
                size: 60,
                onTap: {
                    if recordingState.active == field {
                        cancelActiveRecording()
                        return
                    }

                    // Check if we should show conflict dialog
                    if let check = onAttemptRecord, !check() {
                        return // Blocked by conflict
                    }

                    beginRecording(for: field, key: key)
                },
                onClear: key.wrappedValue.isEmpty ? nil : {
                    key.wrappedValue = ""
                    syncBehavior()
                }
            )

            // Label to the right
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
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

    private func resetForm() {
        // Reset basic fields
        input = ""
        output = ""
        customName = ""
        description = ""
        isEnabled = true
        validationError = nil
        ruleValidationErrors = []
        showValidationAlert = false

        // Reset advanced section
        showAdvanced = false
        resetAdvanced()

        // Stop any recording
        cancelActiveRecording()
    }

    private func openSettings() {
        // Open settings window without specifying a tab (smart default)
        if let appMenu = NSApp.mainMenu?.items.first?.submenu {
            for item in appMenu.items {
                if item.title.contains("Settings") || item.title.contains("Preferences"),
                   let action = item.action {
                    NSApp.sendAction(action, to: item.target, from: item)
                    return
                }
            }
        }
        // Fallback
        if #available(macOS 13, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    private func openRulesSettings() {
        // Open settings window and navigate to the Rules tab
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NotificationCenter.default.post(name: .openSettingsRules, object: nil)
    }

    // MARK: - Controls Bar (Standalone Mode)

    /// Controls bar for standalone mode - sits below titlebar, right-aligned
    @ViewBuilder
    private var standaloneControlsBar: some View {
        HStack(spacing: 16) {
            // Status indicator on the left - only shown when there are problems
            if systemHasProblems {
                Button {
                    onShowWizard?()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.orange)
                        Text("Setup needed")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
                .help("Open Installation Wizard")
            }

            Spacer()

            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .help("Open Settings")

            Button {
                resetForm()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .help("Reset form")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .task {
            // Check system health on appear
            await checkSystemHealth()
        }
        .onReceive(NotificationCenter.default.publisher(for: .kp_startupRevalidate)) { _ in
            // Refresh system health when startup validation completes or wizard triggers revalidation
            Task {
                await checkSystemHealth()
            }
        }
    }

    /// Check system health to update status indicator
    private func checkSystemHealth() async {
        let context = await kanataManager.inspectSystemContext()
        // Only check KeyPath permissions - Kanata permissions are handled separately
        let hasProblems = !context.permissions.keyPath.hasAllPermissions || !context.services.isHealthy
        await MainActor.run {
            systemHasProblems = hasProblems
        }
    }

    // MARK: - Header Views

    /// Header for sheet (modal) mode
    @ViewBuilder
    private var sheetHeader: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .keyboardShortcut(.cancelAction)
            .help("Close")

            Text("KeyPath")
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.leading, 8)

            Spacer()

            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Open Settings")

            Button {
                resetForm()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Reset form")

            if mode == .edit, onDelete != nil {
                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Delete rule")
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        EmptyView()
    }

    // MARK: - Key Capture

    private func startKeyCapture(into key: Binding<String>, field _: RecordingField) {
        // Stop any previous sequence capture/monitors
        keyboardCapture?.stopCapture()
        sequenceFinalizeTimer?.invalidate()

        if keyboardCapture == nil {
            keyboardCapture = KeyboardCapture()
        }

        guard let capture = keyboardCapture else { return }

        capture.startSequenceCapture(mode: .sequence) { [self] sequence in
            Task { @MainActor in
                // Convert captured sequence to canonical kanata string and update field
                let kanataString = Self.convertSequenceToKanataFormat(sequence)
                key.wrappedValue = kanataString
                syncBehavior()
                refreshValidation()

                // Restart finalize timer to end recording after user stops typing
                sequenceFinalizeTimer?.invalidate()
                sequenceFinalizeTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
                    Task { @MainActor in
                        cancelActiveRecording()
                    }
                }
            }
        }
    }

    // MARK: - Sequence Helpers (borrowed from Mapper)

    private static func convertSequenceToKanataFormat(_ sequence: KeySequence) -> String {
        let keyStrings = sequence.keys.map { keyPress -> String in
            var result = keyPress.baseKey.lowercased()

            // Special key name normalization
            let keyMap: [String: String] = [
                "space": "spc",
                "return": "ret",
                "enter": "ret",
                "escape": "esc",
                "backspace": "bspc",
                "delete": "del"
            ]
            if let mapped = keyMap[result] {
                result = mapped
            }

            // Apply modifiers to base key
            var parts: [String] = []
            if keyPress.modifiers.contains(.command) { parts.append("M-") }
            if keyPress.modifiers.contains(.control) { parts.append("C-") }
            if keyPress.modifiers.contains(.option) { parts.append("A-") }
            if keyPress.modifiers.contains(.shift) { parts.append("S-") }
            parts.append(result)

            return parts.joined()
        }

        // Join with spaces to create kanata sequence
        return keyStrings.joined(separator: " ")
    }

    private func displayLabel(for keyString: String) -> String {
        keyString
            .split(separator: " ")
            .map { KeyDisplayName.display(for: String($0)) }
            .joined(separator: " ")
    }

    // MARK: - Responsive Keycap (Mapper-style, tuned for Editor)

    private struct ResponsiveKeycapView: View {
        let label: String
        let isRecording: Bool
        let maxWidth: CGFloat
        let onTap: () -> Void
        let onClear: (() -> Void)?

        @State private var isHovered = false
        @State private var isPressed = false

        // Sizing constants (smaller than Mapper output keycaps but still flexible)
        private static let baseHeight: CGFloat = 96
        private static let maxHeightMultiplier: CGFloat = 1.5
        private static let minWidth: CGFloat = 96
        private static let horizontalPadding: CGFloat = 18
        private static let verticalPadding: CGFloat = 12
        private static let baseFontSize: CGFloat = 26
        private static let minFontSize: CGFloat = 12
        private static let cornerRadius: CGFloat = 12

        private var hasLiveLabel: Bool {
            !(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || label == "?")
        }

        private var keycapWidth: CGFloat {
            let charWidth = dynamicFontSize * 0.6
            let contentWidth = CGFloat(label.count) * charWidth + Self.horizontalPadding * 2
            let naturalWidth = max(Self.minWidth, contentWidth)
            return min(naturalWidth, maxWidth)
        }

        private var keycapHeight: CGFloat {
            ResponsiveKeycapView.estimatedHeight(label: label, maxWidth: maxWidth)
        }

        private var dynamicFontSize: CGFloat {
            Self.dynamicFontSize(label: label, maxWidth: maxWidth)
        }

        var body: some View {
            ZStack {
                Button {
                    withAnimation(.spring(response: 0.12, dampingFraction: 0.8)) {
                        isPressed = true
                    }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(90))
                        withAnimation(.spring(response: 0.12, dampingFraction: 0.8)) {
                            isPressed = false
                        }
                    }
                    onTap()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: Self.cornerRadius)
                            .fill(backgroundColor)
                            .shadow(color: .black.opacity(0.45), radius: isPressed ? 1 : 2, y: isPressed ? 1 : 2)
                            .overlay(
                                RoundedRectangle(cornerRadius: Self.cornerRadius)
                                    .stroke(borderColor, lineWidth: isRecording ? 2 : 1)
                            )

                        if hasLiveLabel {
                            // Show the actual key label
                            Text(label)
                                .font(.system(size: dynamicFontSize, weight: .medium))
                                .foregroundStyle(foregroundColor)
                                .multilineTextAlignment(.center)
                                .lineSpacing(2)
                                .minimumScaleFactor(Self.minFontSize / Self.baseFontSize)
                                .padding(.horizontal, Self.horizontalPadding)
                                .padding(.vertical, Self.verticalPadding / 1.4)
                        } else {
                            // Empty state: show keyboard icon
                            Image(systemName: "keyboard.badge.eye")
                                .font(.system(size: 28, weight: .medium))
                                .foregroundStyle(isRecording ? foregroundColor : foregroundColor.opacity(0.4))
                        }
                    }
                    .frame(width: keycapWidth, height: keycapHeight)
                    .scaleEffect(isPressed ? 0.95 : 1.0)
                    // Stable REC badge anchored to top-left of the keycap
                    .overlay(alignment: .topLeading) {
                        if isRecording {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                Text("REC")
                                    .font(.caption2.weight(.semibold))
                            }
                            .foregroundStyle(Color.red.opacity(0.9))
                            .padding(8)
                        }
                    }
                }
                .buttonStyle(.plain)
                .focusable(false)
                .animation(.spring(response: 0.18, dampingFraction: 0.75), value: isPressed)
                .animation(.easeInOut(duration: 0.2), value: keycapHeight)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHovered = hovering
                    }
                }

                // Clear button
                if let onClear, !isRecording {
                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                onClear()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .background(
                                        Circle()
                                            .fill(Color.black.opacity(0.35))
                                            .frame(width: 18, height: 18)
                                    )
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                            .offset(x: 6, y: -6)
                        }
                        Spacer()
                    }
                    .frame(width: keycapWidth, height: keycapHeight)
                }
            }
        }

        // MARK: - Styling

        private var foregroundColor: Color {
            Color(red: 0.88, green: 0.93, blue: 1.0)
                .opacity(isPressed ? 1.0 : 0.88)
        }

        private var backgroundColor: Color {
            if isRecording {
                Color.accentColor
            } else if isHovered {
                Color(white: 0.15)
            } else {
                Color(white: 0.08)
            }
        }

        private var borderColor: Color {
            if isRecording {
                Color.accentColor.opacity(0.8)
            } else if isHovered {
                Color.white.opacity(0.28)
            } else {
                Color.white.opacity(0.15)
            }
        }

        // MARK: - Metrics helpers

        private static func dynamicFontSize(label: String, maxWidth: CGFloat) -> CGFloat {
            guard maxWidth < .infinity else { return baseFontSize }

            let availableWidth = maxWidth - horizontalPadding * 2
            let charWidth: CGFloat = baseFontSize * 0.6
            let contentWidth = CGFloat(label.count) * charWidth
            let linesNeeded = max(1, ceil(contentWidth / availableWidth))

            let lineHeight = baseFontSize * 1.25
            let heightNeeded = linesNeeded * lineHeight + verticalPadding * 2
            let maxHeight = baseHeight * maxHeightMultiplier

            if heightNeeded <= maxHeight {
                return baseFontSize
            }

            let availableHeight = maxHeight - verticalPadding * 2
            let scale = availableHeight / (linesNeeded * lineHeight)
            return max(minFontSize, baseFontSize * scale)
        }

        static func estimatedHeight(label: String, maxWidth: CGFloat) -> CGFloat {
            let fontSize = dynamicFontSize(label: label, maxWidth: maxWidth)
            let availableWidth = maxWidth - horizontalPadding * 2
            let charWidth = fontSize * 0.6
            let contentWidth = CGFloat(label.count) * charWidth
            let linesNeeded = max(1, ceil(contentWidth / availableWidth))
            let lineHeight = fontSize * 1.25
            let naturalHeight = linesNeeded * lineHeight + verticalPadding * 2
            let maxHeight = baseHeight * maxHeightMultiplier
            return min(max(baseHeight, naturalHeight), maxHeight)
        }
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

    private func buildRuleForValidation() -> CustomRule {
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)

        // Determine input type based on number of keys and capture mode setting
        let inputType: InputType = {
            let tokens = trimmedInput.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if tokens.count <= 1 {
                return .single
            }
            // Multi-key input: check capture mode setting
            return PreferencesService.shared.isSequenceMode ? .sequence : .chord
        }()

        return CustomRule(
            id: existingRule?.id ?? UUID(),
            title: customName,
            input: trimmedInput,
            output: trimmedOutput,
            isEnabled: isEnabled,
            notes: trimmedDescription.isEmpty ? nil : trimmedDescription,
            createdAt: existingRule?.createdAt ?? Date(),
            behavior: behavior,
            inputType: inputType
        )
    }

    @discardableResult
    private func refreshValidation(showAlert: Bool = false) -> [CustomRuleValidator.ValidationError] {
        guard hasRequiredFields else {
            ruleValidationErrors = []
            validationError = nil
            return []
        }

        let rule = buildRuleForValidation()
        let errors = CustomRuleValidator.validate(rule, existingRules: existingRules)
        ruleValidationErrors = errors
        validationError = errors.first?.errorDescription

        if showAlert, !errors.isEmpty {
            showValidationAlert = true
        }

        return errors
    }
}

// MARK: - Editor Keycap View (R2 Style)

/// Dark keycap-style button for recording key input
private struct EditorKeycapView: View {
    let label: String
    let isRecording: Bool
    let isEmpty: Bool
    var size: CGFloat = 80
    let onTap: () -> Void
    let onClear: (() -> Void)?

    @State private var isHovered = false
    @State private var isPressed = false

    // Sizing
    private var cornerRadius: CGFloat { size > 70 ? 12 : 10 }
    private var fontSize: CGFloat { size > 70 ? 24 : 18 }
    private var emptyFontSize: CGFloat { size > 70 ? 32 : 24 }
    private var recordingIconSize: CGFloat { size > 70 ? 24 : 18 }

    var body: some View {
        ZStack {
            Button {
                withAnimation(.spring(response: 0.1, dampingFraction: 0.8)) {
                    isPressed = true
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
                    withAnimation(.spring(response: 0.1, dampingFraction: 0.8)) {
                        isPressed = false
                    }
                }
                onTap()
            } label: {
                ZStack {
                    // Background
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(backgroundColor)
                        .shadow(color: .black.opacity(0.5), radius: isPressed ? 1 : 2, y: isPressed ? 1 : 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .stroke(borderColor, lineWidth: isRecording ? 2 : 1)
                        )

                    // Content
                    if isEmpty {
                        // Empty state: show keyboard icon
                        Image(systemName: "keyboard.badge.eye")
                            .font(.system(size: recordingIconSize, weight: .medium))
                            .foregroundStyle(isRecording ? foregroundColor : foregroundColor.opacity(0.4))
                    } else {
                        Text(label)
                            .font(.system(size: fontSize, weight: .medium))
                            .foregroundStyle(foregroundColor)
                            .minimumScaleFactor(0.5)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, size > 70 ? 8 : 4)
                    }
                }
                .frame(width: size, height: size)
                .scaleEffect(isPressed ? 0.95 : 1.0)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .animation(.spring(response: 0.15, dampingFraction: 0.6), value: isPressed)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }

            // Clear button (top-right corner)
            if let onClear, !isRecording {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            onClear()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.white.opacity(0.6))
                                .background(
                                    Circle()
                                        .fill(Color.black.opacity(0.3))
                                        .frame(width: 18, height: 18)
                                )
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .offset(x: 6, y: -6)
                    }
                    Spacer()
                }
                .frame(width: size, height: size)
                .opacity(isHovered ? 1 : 0)
            }
        }
    }

    // MARK: - Styling (matching overlay keycap dark style)

    private var foregroundColor: Color {
        Color(red: 0.88, green: 0.93, blue: 1.0)
            .opacity(isPressed ? 1.0 : 0.88)
    }

    private var backgroundColor: Color {
        if isRecording {
            Color.accentColor
        } else if isHovered {
            Color(white: 0.15)
        } else {
            Color(white: 0.08)
        }
    }

    private var borderColor: Color {
        if isRecording {
            Color.accentColor.opacity(0.8)
        } else if isHovered {
            Color.white.opacity(0.3)
        } else {
            Color.white.opacity(0.15)
        }
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
