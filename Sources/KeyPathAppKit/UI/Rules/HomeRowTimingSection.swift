import SwiftUI
#if os(macOS)
    import AppKit
#endif

/// Reusable timing section for Home Row Mods — flat, macOS-native layout.
///
/// Layout:
/// - Header: "Timing" + raw values toggle + reset to defaults
/// - Typing Feel: slider OR raw text fields (mutually exclusive)
/// - Quick tap checkbox + inline slider when checked
/// - Per-finger sensitivity checkbox + sliders when checked
struct HomeRowTimingSection: View {
    @Binding var config: HomeRowModsConfig
    let showsHrmInsights: Bool
    let onConfigChanged: (HomeRowModsConfig) -> Void

    @Environment(\.services) private var services
    @State private var sliderDebounceTask: Task<Void, Never>?
    @State private var showPerFinger: Bool
    @State private var isEditingHoldDuration = false
    @State private var isEditingIdleWindow = false
    private var hrmObservability = HrmObservabilityService.shared

    init(
        config: Binding<HomeRowModsConfig>,
        showsHrmInsights: Bool = false,
        onConfigChanged: @escaping (HomeRowModsConfig) -> Void
    ) {
        _config = config
        self.showsHrmInsights = showsHrmInsights
        self.onConfigChanged = onConfigChanged
        let timing = config.wrappedValue.timing
        _showPerFinger = State(initialValue: !timing.tapOffsets.isEmpty || !timing.holdOffsets.isEmpty)
    }

    private var feelSliderPosition: Double? {
        TypingFeelMapping.sliderPosition(tapWindow: config.timing.tapWindow, holdDelay: config.timing.holdDelay)
    }

    private var effectiveSliderPosition: Double {
        feelSliderPosition ?? 0.5
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // MARK: - Header

            HStack(spacing: 8) {
                Text("Timing")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if config.showExpertTiming {
                            // Turning OFF raw mode — snap values to nearest curve position
                            let snapped = TypingFeelMapping.snapToCurve(
                                tapWindow: config.timing.tapWindow,
                                holdDelay: config.timing.holdDelay
                            )
                            config.timing.tapWindow = snapped.tapWindow
                            config.timing.holdDelay = snapped.holdDelay
                            config.showExpertTiming = false
                        } else {
                            config.showExpertTiming = true
                        }
                    }
                    updateConfig()
                } label: {
                    Label("Raw values", systemImage: "number")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    config.showExpertTiming
                        ? Color.accentColor.opacity(0.15)
                        : Color.clear
                )
                .foregroundStyle(config.showExpertTiming ? Color.accentColor : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(
                            config.showExpertTiming ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.2),
                            lineWidth: 0.5
                        )
                )
                .accessibilityIdentifier("home-row-mods-raw-values-toggle")
                .accessibilityLabel("Raw values mode")
                .accessibilityValue(config.showExpertTiming ? "on" : "off")
                .accessibilityAddTraits(config.showExpertTiming ? .isSelected : [])

                if hasNonDefaultTiming {
                    Button {
                        config.timing = .default
                        config.showExpertTiming = false
                        showPerFinger = false
                        updateConfig()
                    } label: {
                        Label("Reset to defaults", systemImage: "arrow.counterclockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("home-row-mods-timing-reset-defaults")
                }
            }

            // MARK: - Composite Timing Slider

            HStack(spacing: 8) {
                Label("Prefer letters", systemImage: "character.cursor.ibeam")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Slider(
                    value: Binding(
                        get: { 1.0 - effectiveSliderPosition },
                        set: { inverted in
                            let pos = 1.0 - inverted
                            let values = TypingFeelMapping.timingValues(forSliderPosition: pos)
                            if usesTimedTapWindow {
                                config.timing.tapWindow = values.tapWindow
                            }
                            config.timing.holdDelay = values.holdDelay
                            let idleFraction = 1.0 - pos
                            config.timing.requirePriorIdleMs = max(0, Int(50 + idleFraction * 200))
                            debouncedUpdateConfig()
                        }
                    ),
                    in: 0 ... 1,
                    step: 0.05
                ) { editing in
                    isEditingHoldDuration = editing
                }
                .frame(maxWidth: 250)
                .accessibilityIdentifier("home-row-mods-feel-slider")
                .accessibilityLabel("Home row typing feel")
                .accessibilityValue(timingSliderAccessibilityValue)
                .overlay(alignment: .top) {
                    if isEditingHoldDuration {
                        Text("\(config.timing.holdDelay)ms")
                            .font(.caption.weight(.semibold).width(.condensed))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor))
                            .offset(y: -18)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }

                Label("Prefer modifiers", systemImage: "command")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .animation(.easeInOut(duration: 0.15), value: isEditingHoldDuration)

            // MARK: - Advanced: Independent Sliders

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    // Hold duration
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text("Hold duration")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            InfoTip("How long you hold a key before the modifier activates.")
                        }
                        if config.showExpertTiming {
                            HStack(spacing: 16) {
                                if usesTimedTapWindow {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Tap window").font(.caption).foregroundColor(.secondary)
                                        HStack(spacing: 4) {
                                            automationIntegerField(
                                                placeholder: "",
                                                value: Binding(
                                                    get: { config.timing.tapWindow },
                                                    set: { config.timing.tapWindow = $0 }
                                                ),
                                                range: 80 ... 350,
                                                accessibilityIdentifier: "home-row-mods-tap-window-field",
                                                accessibilityLabel: "Tap window"
                                            )
                                            Text("ms").font(.caption).foregroundColor(.secondary)
                                        }
                                    }
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Hold delay").font(.caption).foregroundColor(.secondary)
                                    HStack(spacing: 4) {
                                        automationIntegerField(
                                            placeholder: "",
                                            value: Binding(
                                                get: { config.timing.holdDelay },
                                                set: { config.timing.holdDelay = $0 }
                                            ),
                                            range: 80 ... 350,
                                            accessibilityIdentifier: "home-row-mods-hold-delay-field",
                                            accessibilityLabel: "Hold delay"
                                        )
                                        Text("ms").font(.caption).foregroundColor(.secondary)
                                    }
                                }
                            }
                        } else {
                            HStack(spacing: 8) {
                                Text("Letters feel snappy").font(.caption2).foregroundStyle(.secondary)
                                Slider(value: Binding(
                                    get: { 1.0 - effectiveSliderPosition },
                                    set: {
                                        let v = TypingFeelMapping.timingValues(forSliderPosition: 1.0 - $0)
                                        if usesTimedTapWindow {
                                            config.timing.tapWindow = v.tapWindow
                                        }
                                        config.timing.holdDelay = v.holdDelay
                                        debouncedUpdateConfig()
                                    }
                                ), in: 0 ... 1, step: 0.05)
                                    .accessibilityIdentifier("home-row-mods-hold-duration-advanced")
                                    .accessibilityLabel("Advanced hold duration")
                                    .accessibilityValue(timingSliderAccessibilityValue)
                                Text("Modifiers feel snappy").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Fast typing protection
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Toggle("Fast typing protection", isOn: Binding(
                                get: { config.timing.requirePriorIdleMs > 0 },
                                set: { config.timing.requirePriorIdleMs = $0 ? TimingConfig.defaultPriorIdleMs : 0; updateConfig() }
                            ))
                            .toggleStyle(.checkbox)
                            .font(.subheadline)
                            .accessibilityIdentifier("home-row-mods-fast-typing-protection-toggle")
                            .accessibilityLabel("Fast typing protection")
                            .accessibilityValue(config.timing.requirePriorIdleMs > 0 ? "on" : "off")
                            InfoTip("How long you must pause after typing before holds are allowed. Prevents accidental modifiers mid-word.")
                        }
                        if config.timing.requirePriorIdleMs > 0 {
                            HStack(spacing: 8) {
                                Text("Modifiers work mid-typing").font(.caption2).foregroundStyle(.secondary)
                                if config.showExpertTiming {
                                    automationIntegerField(
                                        placeholder: "",
                                        value: Binding(
                                            get: { config.timing.requirePriorIdleMs },
                                            set: { config.timing.requirePriorIdleMs = $0 }
                                        ),
                                        range: 0 ... 500,
                                        accessibilityIdentifier: "home-row-mods-prior-idle-field",
                                        accessibilityLabel: "Fast typing protection idle window"
                                    )
                                } else {
                                    Slider(value: Binding(
                                        get: { 350.0 - Double(max(config.timing.requirePriorIdleMs, 50)) },
                                        set: { config.timing.requirePriorIdleMs = Int(350.0 - $0); debouncedUpdateConfig() }
                                    ), in: 50 ... 300, step: 10) { editing in
                                        isEditingIdleWindow = editing
                                    }
                                    .accessibilityIdentifier("home-row-mods-prior-idle-advanced")
                                    .accessibilityLabel("Fast typing protection idle window")
                                    .accessibilityValue("\(config.timing.requirePriorIdleMs) ms")
                                    .overlay(alignment: .top) {
                                        if isEditingIdleWindow {
                                            Text("\(config.timing.requirePriorIdleMs)ms")
                                                .font(.caption.weight(.semibold).width(.condensed))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Capsule().fill(Color.accentColor))
                                                .offset(y: -18)
                                                .allowsHitTesting(false)
                                                .transition(.opacity)
                                        }
                                    }
                                }
                                Text("No misfires while typing").font(.caption2).foregroundStyle(.secondary)
                            }
                            .animation(.easeInOut(duration: 0.15), value: isEditingIdleWindow)
                        } // requirePriorIdleMs > 0
                    }
                }
                .padding(.top, 6)
            } label: {
                Text("Adjust independently")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("home-row-mods-adjust-independently-disclosure")
                    .accessibilityLabel("Adjust independently")
            }

            // MARK: - Opposite-Hand Activation

            HStack(spacing: 4) {
                Text("Opposite-hand activation")
                Spacer()
                OppositeHandModeControl(selection: config.oppositeHandMode) { newValue in
                    config.oppositeHandMode = newValue
                    updateConfig()
                }
                .frame(maxWidth: 220)

                InfoTip(
                    "Off: Hold resolves by timing, so holding a home-row key can become its modifier by itself.\n\nOn Press: Hold actions activate when you press a key with the other hand. Faster response, but more opinionated.\n\nOn Release: More forgiving — waits for the other-hand key to be released before committing."
                )
            }

            // MARK: - Quick Tap

            Toggle("Favor tap when another key is pressed (quick tap)", isOn: Binding(
                get: { config.timing.quickTapEnabled },
                set: { newValue in
                    config.timing.quickTapEnabled = newValue
                    updateConfig()
                }
            ))
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("home-row-mods-quick-tap-toggle")
            .accessibilityLabel("Favor tap when another key is pressed (quick tap)")
            .accessibilityValue(config.timing.quickTapEnabled ? "on" : "off")

            if config.timing.quickTapEnabled {
                HStack(spacing: 8) {
                    Text("Faster modifiers")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 90, alignment: .trailing)

                    if config.showExpertTiming {
                        automationIntegerField(
                            placeholder: "",
                            value: Binding(
                                get: { config.timing.quickTapTermMs },
                                set: { config.timing.quickTapTermMs = $0 }
                            ),
                            range: 0 ... 120,
                            accessibilityIdentifier: "home-row-mods-quick-tap-term-field",
                            accessibilityLabel: "Quick tap extra time"
                        )
                    } else {
                        Slider(value: Binding(
                            get: { Double(config.timing.quickTapTermMs) },
                            set: { newValue in
                                config.timing.quickTapTermMs = Int(newValue)
                                debouncedUpdateConfig()
                            }
                        ), in: 0 ... 80, step: 5)
                            .accessibilityIdentifier("home-row-mods-quick-tap-term-slider")
                            .accessibilityLabel("Quick tap extra time")
                            .accessibilityValue("\(config.timing.quickTapTermMs) ms")
                    }

                    Text("Fewer misfires")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 90, alignment: .leading)
                }

                Text(quickTapHelperText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 88)
            }

            // MARK: - Per-Finger Sensitivity

            Divider()
                .padding(.vertical, 4)

            HStack(spacing: 4) {
                Text("Per-finger sensitivity")
                    .font(.body)

                InfoTip("Add extra delay for slower fingers to prevent accidental holds.")
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(TypingFeelMapping.FingerGroup.allCases, id: \.self) { finger in
                    fingerSliderRow(finger: finger)
                }

                if config.showExpertTiming, hasAnyPerKeyOffsets {
                    Divider()
                        .padding(.vertical, 2)
                    perKeyOffsetFields
                }
            }

            if showsHrmInsights {
                Divider()
                    .padding(.vertical, 4)
                hrmInsightsSection
            }
        }
        .animation(.easeInOut(duration: 0.2), value: config.timing.quickTapEnabled)
        .animation(.easeInOut(duration: 0.2), value: showPerFinger)
        .animation(.easeInOut(duration: 0.15), value: config.showExpertTiming)
        .onAppear {
            showPerFinger = hasAnyPerKeyOffsets
            if showsHrmInsights {
                hrmObservability.startMonitoring(port: services.preferences.tcpServerPort)
            }
        }
    }

    // MARK: - Finger Slider Row

    private static let fingerEmoji: [TypingFeelMapping.FingerGroup: String] = [
        .pinky: "\u{1F91E}", // crossed fingers (smallest finger gesture)
        .ring: "\u{1F48D}", // ring
        .middle: "\u{1F595}", // middle finger
        .index: "\u{261D}\u{FE0F}" // index pointing up
    ]

    private var isTopRow: Bool {
        TypingFeelMapping.usesTopRow(config.enabledKeys)
    }

    private func fingerSliderRow(finger: TypingFeelMapping.FingerGroup) -> some View {
        let sensitivity = TypingFeelMapping.fingerSensitivity(for: finger, in: config.timing, topRow: isTopRow)
        let isCustom = sensitivity == nil
        let displayValue = sensitivity ?? 0
        let emoji = Self.fingerEmoji[finger] ?? ""

        return HStack(spacing: 8) {
            Text("\(emoji) \(finger.displayName)")
                .font(.caption)
                .frame(width: 80, alignment: .trailing)

            if config.showExpertTiming {
                automationIntegerField(
                    placeholder: "",
                    value: Binding(
                        get: { displayValue },
                        set: {
                            TypingFeelMapping.applyFingerSensitivity($0, for: finger, to: &config.timing, topRow: isTopRow)
                        }
                    ),
                    range: 0 ... 120,
                    accessibilityIdentifier: "home-row-mods-finger-\(finger.rawValue)-field",
                    accessibilityLabel: "\(finger.displayName) finger sensitivity"
                )
            } else {
                Slider(
                    value: Binding(
                        get: { Double(displayValue) },
                        set: { newValue in
                            TypingFeelMapping.applyFingerSensitivity(Int(newValue), for: finger, to: &config.timing, topRow: isTopRow)
                            debouncedUpdateConfig()
                        }
                    ),
                    in: 0 ... 80,
                    step: 5
                )
                .accessibilityIdentifier("home-row-mods-finger-\(finger.rawValue)-slider")
                .accessibilityLabel("\(finger.displayName) finger sensitivity")
                .accessibilityValue("\(displayValue) ms")
            }

            if isCustom {
                Text("Mixed")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(width: 50, alignment: .trailing)
            } else {
                Text(displayValue > 0 ? "+\(displayValue)ms" : "0ms")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
            }
        }
    }

    // MARK: - Per-Key Offset Fields (Expert, shown inside per-finger section)

    private var perKeyOffsetFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Per-key tap offsets (ms)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ForEach(chunks(of: HomeRowModsConfig.allKeys, size: 4), id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(row, id: \.self) { key in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(key.uppercased())
                                .font(.caption)
                                .foregroundColor(.secondary)
                            automationIntegerField(
                                placeholder: "0",
                                value: Binding(
                                    get: { config.timing.tapOffsets[key] ?? 0 },
                                    set: { newValue in
                                        if newValue == 0 {
                                            config.timing.tapOffsets.removeValue(forKey: key)
                                        } else {
                                            config.timing.tapOffsets[key] = newValue
                                        }
                                    }
                                ),
                                range: -100 ... 200,
                                accessibilityIdentifier: "home-row-mods-tap-offset-\(key)-field",
                                accessibilityLabel: "\(key.uppercased()) tap offset"
                            )
                        }
                    }
                    Spacer()
                }
            }

            Divider()

            Text("Per-key hold offsets (ms)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ForEach(chunks(of: HomeRowModsConfig.allKeys, size: 4), id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(row, id: \.self) { key in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(key.uppercased())
                                .font(.caption)
                                .foregroundColor(.secondary)
                            automationIntegerField(
                                placeholder: "0",
                                value: Binding(
                                    get: { config.timing.holdOffsets[key] ?? 0 },
                                    set: { newValue in
                                        if newValue == 0 {
                                            config.timing.holdOffsets.removeValue(forKey: key)
                                        } else {
                                            config.timing.holdOffsets[key] = newValue
                                        }
                                    }
                                ),
                                range: -100 ... 200,
                                accessibilityIdentifier: "home-row-mods-hold-offset-\(key)-field",
                                accessibilityLabel: "\(key.uppercased()) hold offset"
                            )
                        }
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - HRM Insights

    private var hrmInsightsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("HRM Insights")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(hrmObservability.availability.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(hrmAvailabilityColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(hrmAvailabilityColor.opacity(0.12))
                    .clipShape(Capsule())
                    .accessibilityIdentifier("home-row-mods-hrm-availability-badge")
                    .accessibilityLabel("Home row mods telemetry availability")
                    .accessibilityValue(hrmObservability.availability.displayName)
            }

            Text("Live observability for home-row tap/hold decisions. Use calibration to preview conservative timing suggestions before applying.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("Start 60s Calibration") {
                    hrmObservability.startCalibration(durationSeconds: 60)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hrmObservability.supportsHrmStats || hrmObservability.calibrationState == .running)
                .accessibilityIdentifier("home-row-mods-hrm-start-calibration-button")
                .accessibilityHint(hrmCalibrationButtonAccessibilityHint)

                Button("Refresh Stats") {
                    hrmObservability.refreshNow()
                }
                .buttonStyle(.bordered)
                .disabled(!hrmObservability.supportsHrmStats)
                .accessibilityIdentifier("home-row-mods-hrm-refresh-stats-button")
                .accessibilityHint(hrmRefreshButtonAccessibilityHint)
            }

            if !hrmObservability.supportsHrmStats {
                Text(hrmStatsUnavailableMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("home-row-mods-hrm-stats-unavailable")
            }

            if hrmObservability.calibrationState == .running {
                Text("Calibration running: \(hrmObservability.calibrationRemainingSeconds)s remaining")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("home-row-mods-hrm-calibration-running")
            } else if case let .failed(message) = hrmObservability.calibrationState {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("home-row-mods-hrm-calibration-error")
            }

            if let stats = hrmObservability.latestStats {
                hrmStatsSummary(stats)
            } else {
                Text("No HRM stats available yet. Trigger some typing activity, then refresh stats.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !hrmObservability.recentTraceEvents.isEmpty {
                liveTraceSection
            }

            if !hrmObservability.recommendations.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recommendation Preview")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(hrmObservability.recommendations) { recommendation in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recommendation.title)
                                .font(.caption.weight(.semibold))
                            Text(recommendation.details)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }

                    Button("Apply Suggestions") {
                        var updatedConfig = config
                        hrmObservability.applyRecommendations(to: &updatedConfig)
                        config = updatedConfig
                        updateConfig()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("home-row-mods-hrm-apply-suggestions-button")
                }
            }
        }
    }

    private func hrmStatsSummary(_ stats: KanataHrmStatsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                hrmMetricChip(title: "Decisions", value: "\(stats.decisionsTotal)")
                hrmMetricChip(title: "Tap/Hold", value: "\(stats.tapCount)/\(stats.holdCount)")
                hrmMetricChip(title: "Avg Latency", value: "\(Int(stats.avgDecideLatencyMs.rounded()))ms")
            }

            if !hrmObservability.topReasons.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Top Reasons")
                        .font(.caption.weight(.semibold))
                    ForEach(hrmObservability.topReasons) { reason in
                        Text("• \(reason.reason.displayName): \(reason.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !hrmObservability.perKeyBreakdown.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Per-Key Breakdown")
                        .font(.caption.weight(.semibold))
                    ForEach(hrmObservability.perKeyBreakdown) { breakdown in
                        Text(
                            "\(breakdown.key.uppercased()): \(breakdown.tapCount) tap / \(breakdown.holdCount) hold • \(breakdown.avgLatencyMs)ms avg"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Live Decision Stream

    private var liveTraceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Live Decision Stream")
                .font(.caption.weight(.semibold))

            VStack(alignment: .leading, spacing: 3) {
                ForEach(hrmObservability.recentTraceEvents.suffix(10).reversed()) { event in
                    HStack(spacing: 6) {
                        Text(event.key)
                            .font(.caption.monospaced())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 3))

                        Text(event.decision == .tap ? "tap" : "hold")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(event.decision == .tap ? .blue : .orange)
                            .frame(width: 28, alignment: .leading)

                        Text(event.shortExplanation)
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(event.latencyDisplay)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)

                        Text(event.formattedTimestamp)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .accessibilityIdentifier("home-row-mods-hrm-live-trace")
    }

    private func hrmMetricChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Helpers

    private var quickTapHelperText: String {
        if config.timing.quickTapTermMs == 0 {
            return "No extra time added. Uses base tap window only."
        }
        return "Adds \(config.timing.quickTapTermMs)ms to the tap window during key rolls."
    }

    private var usesTimedTapWindow: Bool {
        !config.oppositeHandMode.isEnabled
    }

    private var timingSliderAccessibilityValue: String {
        if usesTimedTapWindow {
            return "tap window \(config.timing.tapWindow) ms, hold delay \(config.timing.holdDelay) ms"
        }
        return "hold delay \(config.timing.holdDelay) ms"
    }

    private var hasNonDefaultTiming: Bool {
        config.timing != .default || config.showExpertTiming
    }

    private var hasAnyPerKeyOffsets: Bool {
        !config.timing.tapOffsets.isEmpty || !config.timing.holdOffsets.isEmpty
    }

    private var hrmAvailabilityColor: Color {
        switch hrmObservability.availability {
        case .supported:
            .green
        case .traceOnly:
            .blue
        case .unsupported:
            .secondary
        case .disabledInRuntimeConfig:
            .orange
        case .unknown:
            .secondary
        }
    }

    private var hrmStatsUnavailableMessage: String {
        switch hrmObservability.availability {
        case .traceOnly:
            "Live decisions are available, but stats and calibration require Kanata's hrm-stats capability."
        case .unsupported:
            "Stats and calibration are unavailable because this Kanata build does not advertise HRM telemetry."
        case .unknown:
            "Stats and calibration are unavailable until Kanata reports HRM telemetry support."
        case .disabledInRuntimeConfig:
            "Stats and calibration are unavailable because HRM telemetry is disabled in the active runtime config."
        case .supported:
            ""
        }
    }

    private var hrmCalibrationButtonAccessibilityHint: String {
        if hrmObservability.calibrationState == .running {
            return "Calibration is already running."
        }
        if !hrmObservability.supportsHrmStats {
            return hrmStatsUnavailableMessage
        }
        return "Starts a 60 second home row mods calibration."
    }

    private var hrmRefreshButtonAccessibilityHint: String {
        if !hrmObservability.supportsHrmStats {
            return hrmStatsUnavailableMessage
        }
        return "Refreshes home row mods statistics from Kanata."
    }

    @ViewBuilder
    private func automationIntegerField(
        placeholder: String,
        value: Binding<Int>,
        range: ClosedRange<Int>? = nil,
        accessibilityIdentifier: String,
        accessibilityLabel: String
    ) -> some View {
        #if os(macOS)
            AccessibleIntegerField(
                placeholder: placeholder,
                value: value,
                range: range,
                accessibilityIdentifier: accessibilityIdentifier,
                accessibilityLabel: accessibilityLabel,
                onValueChanged: { _ in updateConfig() }
            )
            .frame(width: 70, height: 22)
        #else
            TextField(placeholder, value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
                .accessibilityIdentifier(accessibilityIdentifier)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue("\(value.wrappedValue) ms")
        #endif
    }

    private func updateConfig() {
        onConfigChanged(config)
    }

    private func debouncedUpdateConfig() {
        sliderDebounceTask?.cancel()
        sliderDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            updateConfig()
        }
    }
}

// MARK: - Private Helpers

private func chunks<T>(of array: [T], size: Int) -> [[T]] {
    stride(from: 0, to: array.count, by: size).map { start in
        Array(array[start ..< min(start + size, array.count)])
    }
}

private struct OppositeHandModeControl: View {
    let selection: OppositeHandMode
    let onSelection: (OppositeHandMode) -> Void

    private let modes: [OppositeHandMode] = [.off, .press, .release]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(modes, id: \.self) { mode in
                Button {
                    onSelection(mode)
                } label: {
                    Text(mode.displayName)
                        .font(.subheadline.weight(selection == mode ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == mode ? Color.white : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selection == mode ? Color.accentColor : Color.clear)
                )
                .accessibilityIdentifier("home-row-mods-opposite-hand-\(mode.rawValue)")
                .accessibilityLabel(mode.displayName)
                .accessibilityValue(selection == mode ? "selected" : "not selected")
                .accessibilityAddTraits(selection == mode ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home-row-mods-opposite-hand-picker")
        .accessibilityLabel("Opposite-hand activation mode")
        .accessibilityValue(selection.displayName)
    }
}
