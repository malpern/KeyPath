import AppKit
import KeyPathCore
import SwiftUI

struct OverlayAvailableWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct RightRoundedRectangle: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width / 2, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + r),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct InspectorMaskedHost<Content: View>: NSViewRepresentable {
    var content: Content
    var reveal: CGFloat
    var totalWidth: CGFloat
    var leadingGap: CGFloat
    var slideOffset: CGFloat
    var opacity: CGFloat
    var debugEnabled: Bool

    func makeNSView(context _: Context) -> InspectorMaskedHostingView<Content> {
        InspectorMaskedHostingView(content: content)
    }

    func updateNSView(_ nsView: InspectorMaskedHostingView<Content>, context _: Context) {
        nsView.update(
            content: content,
            reveal: reveal,
            totalWidth: totalWidth,
            leadingGap: leadingGap,
            slideOffset: slideOffset,
            opacity: opacity,
            debugEnabled: debugEnabled
        )
    }
}

final class InspectorMaskedHostingView<Content: View>: NSView {
    private let hostingView: NSHostingView<Content>
    private let maskLayer = CALayer()
    private var reveal: CGFloat = 0
    private var totalWidth: CGFloat = 0
    private var leadingGap: CGFloat = 0
    private var slideOffset: CGFloat = 0
    private var contentOpacity: CGFloat = 1
    private var debugEnabled: Bool = false
    private var lastDebugLogTime: CFTimeInterval = 0

    init(content: Content) {
        hostingView = NSHostingView(rootView: content)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.mask = maskLayer
        maskLayer.backgroundColor = NSColor.black.cgColor

        hostingView.wantsLayer = true
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        addSubview(hostingView)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        content: Content,
        reveal: CGFloat,
        totalWidth: CGFloat,
        leadingGap: CGFloat,
        slideOffset: CGFloat,
        opacity: CGFloat,
        debugEnabled: Bool
    ) {
        hostingView.rootView = content
        self.reveal = reveal
        self.totalWidth = totalWidth
        self.leadingGap = leadingGap
        self.slideOffset = slideOffset
        contentOpacity = opacity
        self.debugEnabled = debugEnabled
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let bounds = bounds
        hostingView.frame = bounds.offsetBy(dx: slideOffset, dy: 0)
        hostingView.alphaValue = contentOpacity

        let widthBasis = totalWidth > 0 ? totalWidth : bounds.width
        let gap = max(0, min(leadingGap, widthBasis))
        let panelWidth = max(0, widthBasis - gap)
        let width = max(0, min(widthBasis, gap + panelWidth * reveal))
        maskLayer.frame = CGRect(x: 0, y: 0, width: width, height: bounds.height)

        guard debugEnabled else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastDebugLogTime > 0.2 else { return }
        lastDebugLogTime = now
        let revealStr = String(format: "%.3f", reveal)
        let slideStr = String(format: "%.1f", slideOffset)
        let widthStr = String(format: "%.1f", width)
        let gapStr = String(format: "%.1f", gap)
        let opacityStr = String(format: "%.2f", contentOpacity)
        AppLogger.shared.log(
            "🧱 [OverlayInspectorMask] bounds=\(bounds.size.debugDescription) reveal=\(revealStr) slide=\(slideStr) gap=\(gapStr) maskW=\(widthStr) opacity=\(opacityStr)"
        )
    }
}

struct OverlayInspectorPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let selectedSection: InspectorSection
    let onSelectSection: (InspectorSection) -> Void
    let fadeAmount: CGFloat
    let isMapperAvailable: Bool
    let kanataViewModel: KanataViewModel?
    let inspectorReveal: CGFloat
    let inspectorTotalWidth: CGFloat
    let inspectorLeadingGap: CGFloat
    let healthIndicatorState: HealthIndicatorState
    let onHealthTap: () -> Void
    /// Callback when keymap selection changes (keymapId, includePunctuation)
    var onKeymapChanged: ((String, Bool) -> Void)?
    /// Whether settings shelf (gear mode) is active
    let isSettingsShelfActive: Bool
    /// Toggle settings shelf (gear mode)
    let onToggleSettingsShelf: () -> Void
    /// Callback when a key is selected in the mapper drawer (keyCode or nil to clear)
    var onKeySelected: ((UInt16?) -> Void)?
    /// Layer key map for looking up actual mappings (passed from parent view)
    var layerKeyMap: [UInt16: LayerKeyInfo] = [:]
    /// Whether custom rules exist (for showing Custom Rules tab)
    var hasCustomRules: Bool = false
    /// Global custom rules for displaying in Custom Rules tab
    var customRules: [CustomRule] = []
    /// App keymaps for displaying in Custom Rules tab
    var appKeymaps: [AppKeymap] = []
    /// Callback when an app rule is deleted
    var onDeleteAppRule: ((AppKeymap, AppKeyOverride) -> Void)?
    /// Callback when a global rule is deleted
    var onDeleteGlobalRule: ((CustomRule) -> Void)?
    /// Callback when user wants to reset all custom rules
    var onResetAllRules: (() -> Void)?
    /// Callback when user wants to create a new app rule
    var onCreateNewAppRule: (() -> Void)?
    /// Callback when hovering a rule row - passes inputKey for keyboard highlighting
    var onRuleHover: ((String?) -> Void)?

    @AppStorage(KeymapPreferences.keymapIdKey) private var selectedKeymapId: String = LogicalKeymap.defaultId
    @AppStorage(KeymapPreferences.includePunctuationStoreKey) private var includePunctuationStore: String = "{}"
    @AppStorage(LayoutPreferences.layoutIdKey) private var selectedLayoutId: String = LayoutPreferences.defaultLayoutId
    @AppStorage("overlayColorwayId") private var selectedColorwayId: String = GMKColorway.default.id

    /// Category to scroll to in physical layout grid
    @State private var scrollToLayoutCategory: LayoutCategory?

    /// Which slide-over panel is currently open (nil = none)
    @State private var activeDrawerPanel: DrawerPanel?

    /// Binding for whether any panel is open
    private var isPanelPresented: Binding<Bool> {
        Binding(
            get: { activeDrawerPanel != nil },
            set: { if !$0 { activeDrawerPanel = nil } }
        )
    }

    /// Title for the currently open panel
    private var panelTitle: String {
        activeDrawerPanel?.title ?? ""
    }

    private var includePunctuation: Bool {
        KeymapPreferences.includePunctuation(for: selectedKeymapId, store: includePunctuationStore)
    }

    private var visibleInspectorWidth: CGFloat {
        let gap = max(0, min(inspectorLeadingGap, inspectorTotalWidth))
        let panelWidth = max(0, inspectorTotalWidth - gap)
        let width = gap + panelWidth * inspectorReveal
        return max(0, min(inspectorTotalWidth, width))
    }

    var body: some View {
        let showDrawerDebugOutline = false
        // SlideOverContainer wraps entire drawer content (tabs + content) so panel covers everything
        SlideOverContainer(
            isPresented: isPanelPresented,
            panelTitle: panelTitle,
            mainContent: {
                VStack(spacing: 8) {
                    // Toolbar with section tabs
                    InspectorPanelToolbar(
                        isDark: isDark,
                        selectedSection: selectedSection,
                        onSelectSection: onSelectSection,
                        isMapperAvailable: isMapperAvailable,
                        healthIndicatorState: healthIndicatorState,
                        hasCustomRules: hasCustomRules,
                        isSettingsShelfActive: isSettingsShelfActive,
                        onToggleSettingsShelf: onToggleSettingsShelf
                    )

                    // Content based on selected section
                    if selectedSection == .launchers {
                        // Launchers section fills available space with button pinned to bottom
                        launchersContent
                            .padding(.horizontal, 12)
                            .padding(.bottom, 6)
                    } else if selectedSection == .mapper {
                        // Mapper section fills available space with layer button pinned to bottom
                        mapperContent
                            .padding(.horizontal, 12)
                            .padding(.bottom, 6)
                    } else if selectedSection == .layout {
                        // Physical layout has its own ScrollView with ScrollViewReader for anchoring
                        physicalLayoutContent
                    } else if selectedSection == .customRules {
                        // Custom rules browser (global + app-specific)
                        customRulesContent
                            .padding(.horizontal, 12)
                            .padding(.bottom, 6)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                switch selectedSection {
                                case .mapper:
                                    EmptyView() // Handled above
                                case .keyboard:
                                    keymapsContent
                                case .layout:
                                    EmptyView() // Handled above
                                case .keycaps:
                                    keycapsContent
                                case .sounds:
                                    soundsContent
                                case .launchers:
                                    EmptyView() // Handled above
                                case .customRules:
                                    EmptyView() // Handled above
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 6)
                        }
                    }
                }
            },
            panelContent: {
                switch activeDrawerPanel {
                case .tapHold:
                    tapHoldPanelContent
                case .launcherSettings:
                    launcherCustomizePanelContent
                case nil:
                    EmptyView()
                }
            }
        )
        .saturation(Double(1 - fadeAmount)) // Monochromatic when faded
        .opacity(Double(1 - fadeAmount * 0.5)) // Fade with keyboard
        .onChange(of: selectedKeymapId) { _, newValue in
            onKeymapChanged?(newValue, includePunctuation)
        }
        .onChange(of: includePunctuationStore) { _, _ in
            onKeymapChanged?(selectedKeymapId, includePunctuation)
        }
        .overlay(alignment: .leading) {
            if showDrawerDebugOutline {
                GeometryReader { proxy in
                    let width = min(proxy.size.width, visibleInspectorWidth)
                    Rectangle()
                        .stroke(Color.red.opacity(0.9), lineWidth: 1)
                        .frame(width: width, height: proxy.size.height, alignment: .leading)
                }
                .allowsHitTesting(false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openTapHoldPanel)) { notification in
            // Extract key info from notification
            if let keyLabel = notification.userInfo?["keyLabel"] as? String {
                tapHoldKeyLabel = keyLabel
            }
            if let keyCode = notification.userInfo?["keyCode"] as? UInt16 {
                tapHoldKeyCode = keyCode
            }
            // Extract selected slot
            if let slotRaw = notification.userInfo?["slot"] as? String,
               let slot = BehaviorSlot(rawValue: slotRaw)
            {
                tapHoldInitialSlot = slot
            }
            // Open the Tap & Hold panel
            withAnimation(.easeInOut(duration: 0.25)) {
                activeDrawerPanel = .tapHold
            }
        }
    }

    // MARK: - Custom Rules Content

    @ViewBuilder
    private var customRulesContent: some View {
        VStack(spacing: 0) {
            // Scrollable list of rule cards (no header - title removed)
            ScrollView {
                LazyVStack(spacing: 10) {
                    // "Everywhere" section for global rules (only shown when rules exist)
                    if !customRules.isEmpty {
                        GlobalRulesCard(
                            rules: customRules,
                            onEdit: { rule in
                                editGlobalRule(rule: rule)
                            },
                            onDelete: { rule in
                                onDeleteGlobalRule?(rule)
                            },
                            onAddRule: {
                                // Switch to mapper with no app condition (global/everywhere)
                                onSelectSection(.mapper)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    NotificationCenter.default.post(
                                        name: .mapperSetAppCondition,
                                        object: nil,
                                        userInfo: ["bundleId": "", "displayName": ""]
                                    )
                                }
                            },
                            onRuleHover: onRuleHover
                        )
                    }

                    // App-specific rules
                    ForEach(appKeymaps) { keymap in
                        AppRuleCard(
                            keymap: keymap,
                            onEdit: { override in
                                editAppRule(keymap: keymap, override: override)
                            },
                            onDelete: { override in
                                onDeleteAppRule?(keymap, override)
                            },
                            onAddRule: {
                                addRuleForApp(keymap: keymap)
                            },
                            onRuleHover: onRuleHover
                        )
                    }
                }
            }

            Spacer()

            // Bottom action bar with reset and add buttons (anchored to bottom right)
            HStack {
                Spacer()
                // Reset all rules button
                Button { onResetAllRules?() } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("custom-rules-reset-button")
                .accessibilityLabel("Reset all custom rules")
                .help("Reset all custom rules")

                // New rule button
                Button { onCreateNewAppRule?() } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("custom-rules-new-button")
                .accessibilityLabel("Create new custom rule")
                .help("Create new custom rule")
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Custom Rules Actions

    private func editAppRule(keymap: AppKeymap, override: AppKeyOverride) {
        // Open mapper with this app's context and rule preloaded
        // Use UserDefaults directly since @AppStorage can't be accessed from nested functions
        UserDefaults.standard.set(InspectorSection.mapper.rawValue, forKey: "inspectorSection")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Convert input key label to keyCode for proper keyboard highlighting
            let keyCode = LogicalKeymap.keyCode(forQwertyLabel: override.inputKey) ?? 0
            let userInfo: [String: Any] = [
                "keyCode": keyCode,
                "inputKey": override.inputKey,
                "outputKey": override.outputAction,
                "appBundleId": keymap.mapping.bundleIdentifier,
                "appDisplayName": keymap.mapping.displayName
            ]
            NotificationCenter.default.post(
                name: .mapperDrawerKeySelected,
                object: nil,
                userInfo: userInfo
            )
        }
    }

    private func addRuleForApp(keymap: AppKeymap) {
        // Open mapper with this app's context (no rule preloaded)
        // Use UserDefaults directly since @AppStorage can't be accessed from nested functions
        UserDefaults.standard.set(InspectorSection.mapper.rawValue, forKey: "inspectorSection")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Set the app condition on the mapper view model
            NotificationCenter.default.post(
                name: .mapperSetAppCondition,
                object: nil,
                userInfo: [
                    "bundleId": keymap.mapping.bundleIdentifier,
                    "displayName": keymap.mapping.displayName
                ]
            )
        }
    }

    private func editGlobalRule(rule: CustomRule) {
        // Open mapper with the global rule preloaded (no app condition)
        onSelectSection(.mapper)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Convert input key label to keyCode for proper keyboard highlighting
            let keyCode = LogicalKeymap.keyCode(forQwertyLabel: rule.input) ?? 0
            let userInfo: [String: Any] = [
                "keyCode": keyCode,
                "inputKey": rule.input,
                "outputKey": rule.output
                // No appBundleId means global/everywhere
            ]
            NotificationCenter.default.post(
                name: .mapperDrawerKeySelected,
                object: nil,
                userInfo: userInfo
            )
        }
    }

    // MARK: - Keymaps Content

    @ViewBuilder
    private var keymapsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Alt layouts section (QWERTY + ergonomic layouts) - no header
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                // QWERTY first
                KeymapCard(
                    keymap: LogicalKeymap.qwertyUS,
                    isSelected: selectedKeymapId == LogicalKeymap.qwertyUS.id,
                    isDark: isDark,
                    fadeAmount: fadeAmount
                ) {
                    selectedKeymapId = LogicalKeymap.qwertyUS.id
                }

                // Then alt layouts
                ForEach(LogicalKeymap.altLayouts) { keymap in
                    KeymapCard(
                        keymap: keymap,
                        isSelected: selectedKeymapId == keymap.id,
                        isDark: isDark,
                        fadeAmount: fadeAmount
                    ) {
                        selectedKeymapId = keymap.id
                    }
                }
            }

            // International layouts section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("International")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.7))
                        .textCase(.uppercase)
                        .tracking(0.8)
                    Spacer()
                }
                .padding(.leading, 4)
                .padding(.trailing, 4)
                .padding(.top, 8)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(LogicalKeymap.internationalLayouts) { keymap in
                        KeymapCard(
                            keymap: keymap,
                            isSelected: selectedKeymapId == keymap.id,
                            isDark: isDark,
                            fadeAmount: fadeAmount
                        ) {
                            selectedKeymapId = keymap.id
                        }
                    }
                }
            }

            // Link to international physical layouts
            Button {
                onSelectSection(.layout)
                // Set scroll target after tab switch to ensure view is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    scrollToLayoutCategory = .international
                }
            } label: {
                HStack(spacing: 4) {
                    Text("International physical layouts")
                        .font(.system(size: 11))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .accessibilityIdentifier("international-physical-layouts-link")
        }
    }

    // MARK: - Mapper Content

    @ViewBuilder
    private var mapperContent: some View {
        // Use a single OverlayMapperSection instance to maintain view identity across health state changes.
        // Previously, separate instances for .unhealthy/.checking/.healthy caused onAppear to reset
        // the selected key when health state changed (e.g., after clicking a rule from the rules panel).
        let showMapper: Bool = {
            if isMapperAvailable { return true }
            if healthIndicatorState == .checking { return true }
            if case .unhealthy = healthIndicatorState { return true }
            return false
        }()
        if showMapper {
            OverlayMapperSection(
                isDark: isDark,
                kanataViewModel: kanataViewModel,
                healthIndicatorState: healthIndicatorState,
                onHealthTap: onHealthTap,
                fadeAmount: fadeAmount,
                onKeySelected: onKeySelected,
                layerKeyMap: layerKeyMap
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            unavailableSection(
                title: "Mapper Unavailable",
                message: "Finish setup to enable quick remapping in the overlay."
            )
        }
    }

    // MARK: - Tap & Hold Panel State (Apple-style 80/20 design)

    /// Key label being configured in the Tap & Hold panel
    @State private var tapHoldKeyLabel: String = "A"
    /// Key code being configured
    @State private var tapHoldKeyCode: UInt16? = 0
    /// Initially selected behavior slot when panel opens
    @State private var tapHoldInitialSlot: BehaviorSlot = .tap
    /// Tap behavior action
    @State private var tapHoldTapAction: BehaviorAction = .key("a")
    /// Hold behavior action
    @State private var tapHoldHoldAction: BehaviorAction = .none
    /// Double tap behavior action
    /// Tap + Hold behavior action
    @State private var tapHoldComboAction: BehaviorAction = .none
    /// Responsiveness level (maps to timing thresholds)
    @State private var tapHoldResponsiveness: ResponsivenessLevel = .balanced
    /// Use tap immediately when typing starts
    @State private var tapHoldUseTapImmediately: Bool = true

    // MARK: - Legacy Customize Panel State (deprecated - use Tap & Hold panel)

    /// Hold action for tap-hold configuration
    @State private var customizeHoldAction: String = ""
    /// Double tap action
    @State private var customizeDoubleTapAction: String = ""
    /// Additional tap-dance steps (Triple Tap, Quad Tap, etc.)
    @State private var customizeTapDanceSteps: [(label: String, action: String)] = []
    /// Tap timeout in milliseconds
    @State private var customizeTapTimeout: Int = 200
    /// Hold timeout in milliseconds
    @State private var customizeHoldTimeout: Int = 200
    /// Whether to show separate tap/hold timing fields
    @State private var customizeShowTimingAdvanced: Bool = false
    /// Which field is currently recording (nil = none)
    @State private var customizeRecordingField: String?
    /// Local event monitor for key capture
    @State private var customizeKeyMonitor: Any?

    // MARK: - Launcher Customize Panel State

    /// Current launcher activation mode
    @State private var launcherActivationMode: LauncherActivationMode = .holdHyper
    /// Current hyper trigger mode (hold vs tap)
    @State private var launcherHyperTriggerMode: HyperTriggerMode = .hold
    /// Whether browser history sheet is showing
    @State private var showLauncherHistorySuggestions = false
    /// Existing launcher domains (for history import)
    @State private var launcherExistingDomains: Set<String> = []

    /// Labels for tap-dance steps beyond double tap
    private static let tapDanceLabels = ["Triple Tap", "Quad Tap", "Quint Tap"]

    /// Content for the Tap & Hold slide-over panel (Apple-style 80/20 design)
    private var tapHoldPanelContent: some View {
        TapHoldCardView(
            keyLabel: tapHoldKeyLabel,
            keyCode: tapHoldKeyCode,
            initialSlot: tapHoldInitialSlot,
            tapAction: $tapHoldTapAction,
            holdAction: $tapHoldHoldAction,
            comboAction: $tapHoldComboAction,
            responsiveness: $tapHoldResponsiveness,
            useTapImmediately: $tapHoldUseTapImmediately
        )
        .padding(.horizontal, 4)
    }

    /// Content for the slide-over customize panel - tap-hold focused (legacy)
    private var customizePanelContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // On Hold row
            customizeRow(
                label: "On Hold",
                action: customizeHoldAction,
                fieldId: "hold",
                onClear: { customizeHoldAction = "" }
            )

            // Double Tap row
            customizeRow(
                label: "Double Tap",
                action: customizeDoubleTapAction,
                fieldId: "doubleTap",
                onClear: { customizeDoubleTapAction = "" }
            )

            // Triple+ Tap rows (dynamically added)
            ForEach(Array(customizeTapDanceSteps.enumerated()), id: \.offset) { index, step in
                customizeTapDanceRow(index: index, step: step)
            }

            // "+ Triple Tap" link (only if we can add more)
            if customizeTapDanceSteps.count < Self.tapDanceLabels.count {
                HStack(spacing: 16) {
                    Text("")
                        .frame(width: 70)

                    Button {
                        let label = Self.tapDanceLabels[customizeTapDanceSteps.count]
                        customizeTapDanceSteps.append((label: label, action: ""))
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle")
                                .font(.caption)
                            Text(Self.tapDanceLabels[customizeTapDanceSteps.count])
                                .font(.subheadline)
                        }
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("customize-add-tap-dance")
                    .accessibilityLabel("Add \(Self.tapDanceLabels[customizeTapDanceSteps.count])")

                    Spacer()
                }
            }

            // Timing row
            customizeTimingRow

            Spacer()
        }
        .padding(.horizontal, 12)
        .onDisappear {
            stopCustomizeRecording()
        }
    }

    /// Content for the launcher customize slide-over panel
    private var launcherCustomizePanelContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Activation section
            VStack(alignment: .leading, spacing: 10) {
                Text("Activation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Activation Mode", selection: $launcherActivationMode) {
                    Text(LauncherActivationMode.holdHyper.displayName)
                        .tag(LauncherActivationMode.holdHyper)
                    Text(LauncherActivationMode.leaderSequence.displayName)
                        .tag(LauncherActivationMode.leaderSequence)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("launcher-customize-activation-mode")
                .onChange(of: launcherActivationMode) { _, _ in
                    saveLauncherConfig()
                }

                // Hyper trigger mode segmented picker (only when Hyper mode selected)
                if launcherActivationMode == .holdHyper {
                    Picker("Trigger Mode", selection: $launcherHyperTriggerMode) {
                        Text(HyperTriggerMode.hold.displayName)
                            .tag(HyperTriggerMode.hold)
                        Text(HyperTriggerMode.tap.displayName)
                            .tag(HyperTriggerMode.tap)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityIdentifier("launcher-customize-trigger-picker")
                    .onChange(of: launcherHyperTriggerMode) { _, _ in
                        saveLauncherConfig()
                    }
                }

                // Description text
                Text(launcherActivationDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Suggestions & Setup section
            VStack(alignment: .leading, spacing: 10) {
                Text("Suggestions")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(spacing: 0) {
            Button {
                Task {
                    await refreshLauncherExistingDomains()
                    showLauncherHistorySuggestions = true
                }
            } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.body)
                                .foregroundStyle(.secondary)
                            Text("Suggest from Browser History")
                                .font(.subheadline)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("launcher-customize-suggest-history")

                    Divider()

                    Button {
                        showLauncherWelcomeFromSettings()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .font(.body)
                                .foregroundStyle(.secondary)
                            Text("Open Launcher Setup")
                                .font(.subheadline)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle())
                    }
            .buttonStyle(.plain)
            .accessibilityIdentifier("launcher-customize-open-setup")
                }
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .onAppear {
            loadLauncherConfig()
        }
        .sheet(isPresented: $showLauncherHistorySuggestions) {
            BrowserHistorySuggestionsView(existingDomains: launcherExistingDomains) { selectedSites in
                addSuggestedSitesToLauncher(selectedSites)
            }
        }
    }

    /// Re-open the launcher welcome dialog from settings.
    private func showLauncherWelcomeFromSettings() {
        Task {
            let collections = await RuleCollectionStore.shared.loadCollections()
            if let launcherCollection = collections.first(where: { $0.id == RuleCollectionIdentifier.launcher }),
               let config = launcherCollection.configuration.launcherGridConfig
            {
                await MainActor.run {
                    var mutableConfig = config
                    LauncherWelcomeWindowController.show(
                        config: Binding(
                            get: { mutableConfig },
                            set: { mutableConfig = $0 }
                        ),
                        onComplete: { finalConfig, _ in
                            saveLauncherWelcomeConfig(finalConfig)
                        },
                        onDismiss: {}
                    )
                }
            }
        }
    }

    private func saveLauncherWelcomeConfig(_ finalConfig: LauncherGridConfig) {
        var updatedConfig = finalConfig
        updatedConfig.hasSeenWelcome = true

        Task {
            let collections = await RuleCollectionStore.shared.loadCollections()
            if var launcherCollection = collections.first(where: { $0.id == RuleCollectionIdentifier.launcher }) {
                launcherCollection.configuration = .launcherGrid(updatedConfig)
                var allCollections = collections
                if let index = allCollections.firstIndex(where: { $0.id == RuleCollectionIdentifier.launcher }) {
                    allCollections[index] = launcherCollection
                    try? await RuleCollectionStore.shared.saveCollections(allCollections)
                }
            }
        }
    }

    /// Description for launcher activation mode
    private var launcherActivationDescription: String {
        switch launcherActivationMode {
        case .holdHyper:
            launcherHyperTriggerMode.description + " Then press a shortcut key."
        case .leaderSequence:
            "Press Leader, then L, then press a shortcut key."
        }
    }

    /// Load launcher config from store
    private func loadLauncherConfig() {
        Task {
            let collections = await RuleCollectionStore.shared.loadCollections()
            if let launcherCollection = collections.first(where: { $0.id == RuleCollectionIdentifier.launcher }),
               let config = launcherCollection.configuration.launcherGridConfig
            {
                await MainActor.run {
                    launcherActivationMode = config.activationMode
                    launcherHyperTriggerMode = config.hyperTriggerMode
                }
            }
        }
    }

    private func refreshLauncherExistingDomains() async {
        let collections = await RuleCollectionStore.shared.loadCollections()
        let domains = collections
            .first(where: { $0.id == RuleCollectionIdentifier.launcher })?
            .configuration
            .launcherGridConfig?
            .mappings
            .compactMap { mapping -> String? in
                if case let .url(domain) = mapping.target {
                    return normalizeDomain(domain)
                }
                return nil
            } ?? []

        await MainActor.run {
            launcherExistingDomains = Set(domains)
        }
    }

    /// Save launcher config to store
    private func saveLauncherConfig() {
        Task {
            var collections = await RuleCollectionStore.shared.loadCollections()
            if let index = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.launcher }) {
                var collection = collections[index]
                if var config = collection.configuration.launcherGridConfig {
                    config.activationMode = launcherActivationMode
                    config.hyperTriggerMode = launcherHyperTriggerMode
                    collection.configuration = .launcherGrid(config)
                    collections[index] = collection
                    try? await RuleCollectionStore.shared.saveCollections(collections)
                    // Notify that rules changed so config regenerates
                    NotificationCenter.default.post(name: .ruleCollectionsChanged, object: nil)
                }
            }
        }
    }

    /// Add suggested sites from browser history to launcher
    private func addSuggestedSitesToLauncher(_ sites: [BrowserHistoryScanner.VisitedSite]) {
        Task {
            var collections = await RuleCollectionStore.shared.loadCollections()
            if let index = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.launcher }) {
                var collection = collections[index]
                if var config = collection.configuration.launcherGridConfig {
                    // Get existing keys
                    var existingKeys = Set(config.mappings.map { LauncherGridConfig.normalizeKey($0.key) })
                    let existingDomains = Set(config.mappings.compactMap { mapping in
                        if case let .url(domain) = mapping.target {
                            return normalizeDomain(domain)
                        }
                        return nil
                    })

                    // Add new mappings for each suggested site
                    for site in sites {
                        if existingDomains.contains(normalizeDomain(site.domain)) {
                            continue
                        }
                        guard let key = LauncherGridConfig.suggestionKeyOrder.first(where: { !existingKeys.contains($0) }) else {
                            continue
                        }

                        existingKeys.insert(key)

                        let mapping = LauncherMapping(
                            key: key,
                            target: .url(site.domain)
                        )
                        config.mappings.append(mapping)
                    }

                    collection.configuration = .launcherGrid(config)
                    collections[index] = collection
                    try? await RuleCollectionStore.shared.saveCollections(collections)
                    NotificationCenter.default.post(name: .ruleCollectionsChanged, object: nil)
                }
            }
        }
    }

    private func normalizeDomain(_ domain: String) -> String {
        let lower = domain.lowercased()
        if lower.hasPrefix("www.") {
            return String(lower.dropFirst(4))
        }
        return lower
    }

    /// Start recording for a specific field
    private func startCustomizeRecording(fieldId: String) {
        // Stop any existing recording first
        stopCustomizeRecording()

        customizeRecordingField = fieldId

        // Add local key event monitor
        customizeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            // Get the key name from the event
            let keyName = keyNameFromEvent(event)

            // Update the appropriate field
            DispatchQueue.main.async {
                setCustomizeFieldValue(fieldId: fieldId, value: keyName)
                stopCustomizeRecording()
            }

            // Consume the event so it doesn't propagate
            return nil
        }
    }

    /// Stop any active recording
    private func stopCustomizeRecording() {
        if let monitor = customizeKeyMonitor {
            NSEvent.removeMonitor(monitor)
            customizeKeyMonitor = nil
        }
        customizeRecordingField = nil
    }

    /// Toggle recording for a field
    private func toggleCustomizeRecording(fieldId: String) {
        if customizeRecordingField == fieldId {
            stopCustomizeRecording()
        } else {
            startCustomizeRecording(fieldId: fieldId)
        }
    }

    /// Set the value for a customize field by ID
    private func setCustomizeFieldValue(fieldId: String, value: String) {
        switch fieldId {
        case "hold":
            customizeHoldAction = value
        case "doubleTap":
            customizeDoubleTapAction = value
        default:
            // Handle tap-dance steps (e.g., "tapDance-0")
            if fieldId.hasPrefix("tapDance-"),
               let indexStr = fieldId.split(separator: "-").last,
               let index = Int(indexStr),
               index < customizeTapDanceSteps.count
            {
                customizeTapDanceSteps[index].action = value
            }
        }
    }

    /// Convert NSEvent to a key name string
    private func keyNameFromEvent(_ event: NSEvent) -> String {
        // Check for modifier-only keys first
        let flags = event.modifierFlags

        // Map common keyCodes to kanata key names
        let keyCodeMap: [UInt16: String] = [
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
            8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
            16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 36: "ret",
            37: "l", 38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",",
            44: "/", 45: "n", 46: "m", 47: ".", 48: "tab", 49: "spc",
            50: "`", 51: "bspc", 53: "esc",
            // Modifiers
            54: "rsft", 55: "lmet", 56: "lsft", 57: "caps", 58: "lalt",
            59: "lctl", 60: "rsft", 61: "ralt", 62: "rctl",
            // Function keys
            122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6",
            98: "f7", 100: "f8", 101: "f9", 109: "f10", 103: "f11", 111: "f12",
            // Arrow keys
            123: "left", 124: "right", 125: "down", 126: "up",
            // Other
            117: "del", 119: "end", 121: "pgdn", 115: "home", 116: "pgup",
        ]

        if let keyName = keyCodeMap[event.keyCode] {
            // Build modifier prefix if any non-modifier key
            var result = ""
            if flags.contains(.control) { result += "C-" }
            if flags.contains(.option) { result += "A-" }
            if flags.contains(.shift), !["lsft", "rsft"].contains(keyName) { result += "S-" }
            if flags.contains(.command) { result += "M-" }
            return result + keyName
        }

        // Fallback to characters
        if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
            return chars.lowercased()
        }

        return "unknown"
    }

    /// A row for hold/double-tap action with mini keycap
    private func customizeRow(label: String, action: String, fieldId: String, onClear: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)

            TapHoldMiniKeycap(
                label: action.isEmpty ? "" : formatKeyForCustomize(action),
                isRecording: customizeRecordingField == fieldId,
                onTap: {
                    toggleCustomizeRecording(fieldId: fieldId)
                }
            )
            .accessibilityIdentifier("customize-\(fieldId)-keycap")
            .accessibilityLabel("\(label) action keycap")

            if !action.isEmpty {
                Button {
                    onClear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("customize-\(fieldId)-clear")
                .accessibilityLabel("Clear \(label.lowercased()) action")
            }

            Spacer()
        }
    }

    /// A row for tap-dance steps (triple tap, quad tap, etc.)
    private func customizeTapDanceRow(index: Int, step: (label: String, action: String)) -> some View {
        HStack(spacing: 12) {
            Text(step.label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)

            TapHoldMiniKeycap(
                label: step.action.isEmpty ? "" : formatKeyForCustomize(step.action),
                isRecording: customizeRecordingField == "tapDance-\(index)",
                onTap: {
                    toggleCustomizeRecording(fieldId: "tapDance-\(index)")
                }
            )
            .accessibilityIdentifier("customize-tapDance-\(index)-keycap")
            .accessibilityLabel("\(step.label) action keycap")

            if !step.action.isEmpty {
                Button {
                    customizeTapDanceSteps[index].action = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("customize-tapDance-\(index)-clear")
                .accessibilityLabel("Clear \(step.label.lowercased()) action")
            }

            // Remove button
            Button {
                customizeTapDanceSteps.remove(at: index)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("customize-tapDance-\(index)-remove")
            .accessibilityLabel("Remove \(step.label.lowercased())")

            Spacer()
        }
    }

    /// Timing configuration row
    private var customizeTimingRow: some View {
        HStack(spacing: 12) {
            Text("Timing")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)

            if customizeShowTimingAdvanced {
                // Separate tap/hold fields
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tap")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            TextField("", value: $customizeTapTimeout, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 50)
                                .accessibilityIdentifier("customize-tap-timeout")
                                .accessibilityLabel("Tap timeout in milliseconds")
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hold")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            TextField("", value: $customizeHoldTimeout, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 50)
                                .accessibilityIdentifier("customize-hold-timeout")
                                .accessibilityLabel("Hold timeout in milliseconds")
                        }
                        Text("ms")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                // Single timing value
                HStack(spacing: 8) {
                    TextField("", value: $customizeTapTimeout, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .accessibilityIdentifier("customize-timing")
                        .accessibilityLabel("Timing in milliseconds")

                    Text("ms")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            // Gear icon to toggle advanced timing
            Button {
                customizeShowTimingAdvanced.toggle()
                if customizeShowTimingAdvanced {
                    customizeHoldTimeout = customizeTapTimeout
                }
            } label: {
                Image(systemName: "gearshape")
                    .font(.subheadline)
                    .foregroundColor(customizeShowTimingAdvanced ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("customize-timing-advanced-toggle")
            .accessibilityLabel(customizeShowTimingAdvanced ? "Use single timing value" : "Use separate tap and hold timing")

            Spacer()
        }
    }

    /// Format a key name for display in customize panel
    private func formatKeyForCustomize(_ key: String) -> String {
        // Handle common modifier names
        switch key.lowercased() {
        case "lmet", "rmet", "met": "⌘"
        case "lalt", "ralt", "alt": "⌥"
        case "lctl", "rctl", "ctl": "⌃"
        case "lsft", "rsft", "sft": "⇧"
        case "space", "spc": "␣"
        case "ret", "return", "enter": "↩"
        case "bspc", "backspace": "⌫"
        case "tab": "⇥"
        case "esc", "escape": "⎋"
        default: key.uppercased()
        }
    }

    // MARK: - Physical Layout Content

    @ViewBuilder
    private var physicalLayoutContent: some View {
        KeyboardSelectionGridView(
            selectedLayoutId: $selectedLayoutId,
            isDark: isDark,
            scrollToCategory: $scrollToLayoutCategory
        )
        // Stable identity prevents scroll position reset when parent re-renders
        // (e.g., when modifier keys like Command trigger pressedKeyCodes updates)
        .id("physical-layout-grid")
    }

    // MARK: - Keycaps Content

    @ViewBuilder
    private var keycapsContent: some View {
        // Colorway cards in 2-column grid
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(GMKColorway.all) { colorway in
                ColorwayCard(
                    colorway: colorway,
                    isSelected: selectedColorwayId == colorway.id,
                    isDark: isDark
                ) {
                    selectedColorwayId = colorway.id
                }
            }
        }
    }

    // MARK: - Sounds Content

    @ViewBuilder
    private var soundsContent: some View {
        TypingSoundsSection(isDark: isDark)
    }

    // MARK: - Launchers Content

    @ViewBuilder
    private var launchersContent: some View {
        OverlayLaunchersSection(
            isDark: isDark,
            fadeAmount: fadeAmount,
            onMappingHover: onRuleHover,
            onCustomize: { activeDrawerPanel = .launcherSettings }
        )
    }

    private var isDark: Bool {
        colorScheme == .dark
    }

    private func unavailableSection(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(white: isDark ? 0.16 : 0.94))
        )
    }
}

/// Card view for a single keymap option with SVG image and info button
private struct KeymapCard: View {
    let keymap: LogicalKeymap
    let isSelected: Bool
    let isDark: Bool
    let fadeAmount: CGFloat
    let onSelect: () -> Void

    @State private var isHovering = false
    @State private var svgImage: NSImage?

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 4) {
                // SVG Image - becomes monochromatic when fading
                if let image = svgImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 45)
                        .saturation(Double(1 - fadeAmount)) // Monochromatic when faded
                } else {
                    keymapPlaceholder
                        .frame(height: 45)
                }

                // Label with info button
                HStack(spacing: 4) {
                    Text(keymap.name)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)

                    Button {
                        NSWorkspace.shared.open(keymap.learnMoreURL)
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("overlay-keymap-button-\(keymap.id)")
        .accessibilityLabel("Select keymap \(keymap.name)")
        .onHover { isHovering = $0 }
        .onAppear { loadSVG() }
    }

    private func loadSVG() {
        // SVGs are at bundle root (not in subdirectory) due to .process() flattening
        guard let svgURL = Bundle.module.url(
            forResource: keymap.iconFilename,
            withExtension: "svg"
        ) else { return }

        svgImage = NSImage(contentsOf: svgURL)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected
                ? Color.accentColor.opacity(0.15)
                : (isHovering ? Color.white.opacity(0.08) : Color.white.opacity(0.04)))
    }

    private var keymapPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.gray.opacity(0.2))
            .overlay(
                Image(systemName: "keyboard")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            )
    }
}

/// Card view for a GMK colorway option with color swatch preview
private struct ColorwayCard: View {
    let colorway: GMKColorway
    let isSelected: Bool
    let isDark: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 4) {
                // Color swatch preview (horizontal bars)
                colorSwatchPreview
                    .frame(height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                // Name and designer
                VStack(spacing: 1) {
                    Text(colorway.name)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)

                    Text(colorway.designer)
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("overlay-colorway-button-\(colorway.id)")
        .accessibilityLabel("Select colorway \(colorway.name)")
        .onHover { isHovering = $0 }
        .help("\(colorway.name) by \(colorway.designer) (\(colorway.year))")
    }

    /// Horizontal color bars showing the colorway
    private var colorSwatchPreview: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                // Alpha base (largest - main key color)
                colorway.alphaBaseColor
                    .frame(width: geo.size.width * 0.35)

                // Mod base
                colorway.modBaseColor
                    .frame(width: geo.size.width * 0.25)

                // Accent base
                colorway.accentBaseColor
                    .frame(width: geo.size.width * 0.2)

                // Legend color (shows as small bar)
                colorway.alphaLegendColor
                    .frame(width: geo.size.width * 0.2)
            }
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected
                ? Color.accentColor.opacity(0.15)
                : (isHovering ? Color.white.opacity(0.08) : Color.white.opacity(0.04)))
    }
}

/// Row view for a physical layout option
private struct PhysicalLayoutRow: View {
    let layout: PhysicalLayout
    let isSelected: Bool
    let isDark: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: layoutIcon)
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(width: 24)

                Text(layout.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityIdentifier("overlay-layout-button-\(layout.id)")
            .accessibilityLabel("Select layout \(layout.name)")
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var layoutIcon: String {
        switch layout.id {
        case "macbook-us": "laptopcomputer"
        case "kinesis-360": "keyboard"
        default: "keyboard"
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected
                ? Color.accentColor.opacity(0.15)
                : (isHovering ? Color.white.opacity(0.08) : Color.white.opacity(0.04)))
    }
}

private enum GearAnchorLocation: Hashable {
    case main
    case settings
}

private struct GearAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: [GearAnchorLocation: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [GearAnchorLocation: Anchor<CGRect>],
        nextValue: () -> [GearAnchorLocation: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct InspectorPanelToolbar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isDark: Bool
    let selectedSection: InspectorSection
    let onSelectSection: (InspectorSection) -> Void
    let isMapperAvailable: Bool
    let healthIndicatorState: HealthIndicatorState
    let hasCustomRules: Bool
    let isSettingsShelfActive: Bool
    let onToggleSettingsShelf: () -> Void
    private let buttonSize: CGFloat = 32
    @State private var isHoveringMapper = false
    @State private var isHoveringCustomRules = false
    @State private var isHoveringKeyboard = false
    @State private var isHoveringLayout = false
    @State private var isHoveringKeycaps = false
    @State private var isHoveringSounds = false
    @State private var isHoveringLaunchers = false
    @State private var isHoveringSettings = false
    @State private var showMainTabs = true
    @State private var showSettingsTabs = false
    @State private var animationToken = 0
    @State private var gearSpinDegrees: Double = 0
    @State private var gearTravelDistance: CGFloat = 0
    @State private var gearPositionX: CGFloat = 0
    @State private var gearPositionY: CGFloat = 0

    var body: some View {
        ZStack(alignment: .leading) {
            mainTabsRow
            settingsTabsRow
        }
        .overlayPreferenceValue(GearAnchorPreferenceKey.self) { anchors in
            GeometryReader { proxy in
                let mainFrame = anchors[.main].map { proxy[$0] }
                let settingsFrame = anchors[.settings].map { proxy[$0] }
                if let mainFrame, let settingsFrame {
                    gearButton(isSelected: showSettingsTabs, rotationDegrees: gearRotationDegrees)
                        .accessibilityIdentifier("inspector-tab-settings")
                        .position(x: gearPositionX, y: gearPositionY)
                        .zIndex(1)
                        .onAppear {
                            // Set initial position without animation
                            let initialFrame = isSettingsShelfActive ? settingsFrame : mainFrame
                            gearPositionX = initialFrame.midX
                            gearPositionY = initialFrame.midY
                            updateGearTravelDistance(mainFrame: mainFrame, settingsFrame: settingsFrame)
                        }
                        .onChange(of: mainFrame) { _, newValue in
                            updateGearTravelDistance(mainFrame: newValue, settingsFrame: settingsFrame)
                            if !isSettingsShelfActive {
                                updateGearPosition(to: newValue)
                            }
                        }
                        .onChange(of: settingsFrame) { _, newValue in
                            updateGearTravelDistance(mainFrame: mainFrame, settingsFrame: newValue)
                            if isSettingsShelfActive {
                                updateGearPosition(to: newValue)
                            }
                        }
                        .onChange(of: isSettingsShelfActive) { _, isActive in
                            let targetFrame = isActive ? settingsFrame : mainFrame
                            updateGearPosition(to: targetFrame)
                        }
                }
            }
        }
        .controlSize(.regular)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        // No background - transparent toolbar
        .onAppear {
            syncShelfVisibility()
        }
        .onChange(of: isSettingsShelfActive) { _, newValue in
            animateShelfTransition(isActive: newValue)
        }
    }

    private var mainTabsRow: some View {
        HStack(spacing: 8) {
            mainTabsContent
                .opacity(showMainTabs ? 1 : 0)
                .allowsHitTesting(showMainTabs)
                .accessibilityHidden(!showMainTabs)
            gearAnchor(.main)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var settingsTabsRow: some View {
        HStack(spacing: 8) {
            gearAnchor(.settings)
            settingsTabsContent
                .opacity(showSettingsTabs ? 1 : 0)
                .allowsHitTesting(showSettingsTabs)
                .accessibilityHidden(!showSettingsTabs)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var gearSlideDuration: Double {
        reduceMotion ? 0 : 0.7 // 4x faster than previous (2.8 / 4)
    }

    private var gearSpinDuration: Double {
        reduceMotion ? 0 : 0.6 // 60% reduction from original (1.5 * 0.4)
    }

    private var tabFadeAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.16)
    }

    private var gearRotationDegrees: Double {
        reduceMotion ? 0 : gearSpinDegrees
    }

    private func gearButton(isSelected: Bool, rotationDegrees: Double) -> some View {
        Button(action: onToggleSettingsShelf) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: buttonSize * 0.5, weight: .semibold))
                .foregroundStyle(isSelected ? Color.accentColor : (isHoveringSettings ? .primary : .secondary))
                .rotationEffect(.degrees(rotationDegrees))
                .frame(width: buttonSize, height: buttonSize)
                .background(gearBackground(isSelected: isSelected))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("inspector-tab-settings")
        .accessibilityLabel(isSelected ? "Close settings shelf" : "Open settings shelf")
        .help("Settings")
        .onHover { isHoveringSettings = $0 }
    }

    private func gearBackground(isSelected: Bool) -> some View {
        let selectedFill = Color.accentColor.opacity(isDark ? 0.38 : 0.26)
        let hoverFill = (isDark ? Color.white : Color.black).opacity(isDark ? 0.08 : 0.08)
        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected ? selectedFill : (isHoveringSettings ? hoverFill : Color.clear))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(isDark ? 0.9 : 0.7) : Color.clear, lineWidth: 1.5)
            )
    }

    private func toolbarButton(
        systemImage: String,
        isSelected: Bool,
        isHovering: Bool,
        onHover: @escaping (Bool) -> Void,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: buttonSize * 0.5, weight: .semibold))
                .foregroundStyle(isSelected ? Color.accentColor : (isHovering ? .primary : .secondary))
                .frame(width: buttonSize, height: buttonSize)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover(perform: onHover)
    }

    private var isMapperTabEnabled: Bool {
        if healthIndicatorState == .checking { return true }
        if case .unhealthy = healthIndicatorState { return true }
        return isMapperAvailable
    }

    private var mainTabsContent: some View {
        Group {
            // Custom Rules first (leftmost) - only shown when custom rules exist
            if hasCustomRules {
                toolbarButton(
                    systemImage: "list.bullet.rectangle",
                    isSelected: selectedSection == .customRules,
                    isHovering: isHoveringCustomRules,
                    onHover: { isHoveringCustomRules = $0 },
                    action: { onSelectSection(.customRules) }
                )
                .accessibilityIdentifier("inspector-tab-custom-rules")
                .accessibilityLabel("Custom Rules")
                .help("Custom Rules")
            }

            // Mapper
            toolbarButton(
                systemImage: "arrow.right.arrow.left",
                isSelected: selectedSection == .mapper,
                isHovering: isHoveringMapper,
                onHover: { isHoveringMapper = $0 },
                action: { onSelectSection(.mapper) }
            )
            .disabled(!isMapperTabEnabled)
            .opacity(isMapperTabEnabled ? 1 : 0.45)
            .accessibilityIdentifier("inspector-tab-mapper")
            .accessibilityLabel("Key Mapper")
            .help("Key Mapper")

            // Launchers
            toolbarButton(
                systemImage: "bolt.fill",
                isSelected: selectedSection == .launchers,
                isHovering: isHoveringLaunchers,
                onHover: { isHoveringLaunchers = $0 },
                action: { onSelectSection(.launchers) }
            )
            .accessibilityIdentifier("inspector-tab-launchers")
            .accessibilityLabel("Quick Launcher")
            .help("Quick Launcher")
        }
    }

    private var settingsTabsContent: some View {
        Group {
            // Keymap (Logical Layout) first
            toolbarButton(
                systemImage: "keyboard",
                isSelected: selectedSection == .keyboard,
                isHovering: isHoveringKeyboard,
                onHover: { isHoveringKeyboard = $0 },
                action: { onSelectSection(.keyboard) }
            )
            .accessibilityIdentifier("inspector-tab-keymap")
            .accessibilityLabel("Keymap")
            .help("Keymap")

            toolbarButton(
                systemImage: "square.grid.3x2",
                isSelected: selectedSection == .layout,
                isHovering: isHoveringLayout,
                onHover: { isHoveringLayout = $0 },
                action: { onSelectSection(.layout) }
            )
            .accessibilityIdentifier("inspector-tab-layout")
            .accessibilityLabel("Physical Layout")
            .help("Physical Layout")

            toolbarButton(
                systemImage: "swatchpalette.fill",
                isSelected: selectedSection == .keycaps,
                isHovering: isHoveringKeycaps,
                onHover: { isHoveringKeycaps = $0 },
                action: { onSelectSection(.keycaps) }
            )
            .accessibilityIdentifier("inspector-tab-keycaps")
            .accessibilityLabel("Keycap Style")
            .help("Keycap Style")

            toolbarButton(
                systemImage: "speaker.wave.2.fill",
                isSelected: selectedSection == .sounds,
                isHovering: isHoveringSounds,
                onHover: { isHoveringSounds = $0 },
                action: { onSelectSection(.sounds) }
            )
            .accessibilityIdentifier("inspector-tab-sounds")
            .accessibilityLabel("Typing Sounds")
            .help("Typing Sounds")
        }
    }

    private func gearAnchor(_ location: GearAnchorLocation) -> some View {
        Color.clear
            .frame(width: buttonSize, height: buttonSize)
            .anchorPreference(key: GearAnchorPreferenceKey.self, value: .bounds) { [location: $0] }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func syncShelfVisibility() {
        showMainTabs = !isSettingsShelfActive
        showSettingsTabs = isSettingsShelfActive
    }

    private func animateShelfTransition(isActive: Bool) {
        animationToken += 1
        let currentToken = animationToken
        if reduceMotion {
            showMainTabs = !isActive
            showSettingsTabs = isActive
            return
        }

        let spinAmount = Double(gearTravelDistance) * gearRotationPerPoint
        let fadeAnimation = tabFadeAnimation

        if isActive {
            withAnimation(fadeAnimation) {
                showMainTabs = false
            }
            withAnimation(.easeInOut(duration: gearSpinDuration)) {
                gearSpinDegrees -= spinAmount
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + gearSlideDuration) {
                guard animationToken == currentToken else { return }
                withAnimation(fadeAnimation) {
                    showSettingsTabs = true
                }
            }
        } else {
            withAnimation(fadeAnimation) {
                showSettingsTabs = false
            }
            withAnimation(.easeInOut(duration: gearSpinDuration)) {
                gearSpinDegrees += spinAmount
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + gearSlideDuration) {
                guard animationToken == currentToken else { return }
                withAnimation(fadeAnimation) {
                    showMainTabs = true
                }
            }
        }
    }

    private var gearRotationPerPoint: Double {
        let circumference = Double.pi * Double(buttonSize)
        guard circumference > 0 else { return 0 }
        return 360.0 / circumference
    }

    private func updateGearTravelDistance(mainFrame: CGRect, settingsFrame: CGRect) {
        let distance = abs(settingsFrame.midX - mainFrame.midX)
        if abs(distance - gearTravelDistance) > 0.5 {
            gearTravelDistance = distance
        }
    }

    private func updateGearPosition(to frame: CGRect) {
        if reduceMotion {
            gearPositionX = frame.midX
            gearPositionY = frame.midY
        } else {
            withAnimation(.spring(response: gearSlideDuration, dampingFraction: 0.85)) {
                gearPositionX = frame.midX
                gearPositionY = frame.midY
            }
        }
    }
}

struct OverlayGlassButtonStyleModifier: ViewModifier {
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.buttonStyle(PlainButtonStyle())
        } else if #available(macOS 26.0, *) {
            content.buttonStyle(GlassButtonStyle())
        } else {
            content.buttonStyle(PlainButtonStyle())
        }
    }
}

struct OverlayGlassEffectModifier: ViewModifier {
    let isEnabled: Bool
    let cornerRadius: CGFloat
    let fallbackFill: Color

    func body(content: Content) -> some View {
        if isEnabled, #available(macOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(fallbackFill)
                )
        }
    }
}

/// Slide-over panels that can appear in the drawer
enum DrawerPanel {
    case tapHold // Tap & Hold configuration (Apple-style 80/20 design)
    case launcherSettings // Launcher activation mode & history suggestions

    var title: String {
        switch self {
        case .tapHold: "Tap & Hold"
        case .launcherSettings: "Launcher Settings"
        }
    }
}

enum InspectorSection: String {
    case mapper
    case customRules // Only shown when custom rules exist
    case keyboard
    case layout
    case keycaps
    case sounds
    case launchers
}

extension InspectorSection {
    var isSettingsShelf: Bool {
        switch self {
        case .keycaps, .sounds, .keyboard, .layout:
            true
        case .mapper, .customRules, .launchers:
            false
        }
    }
}

// MARK: - Preview

#Preview("Keys Pressed") {
    LiveKeyboardOverlayView(
        viewModel: {
            let vm = KeyboardVisualizationViewModel()
            vm.pressedKeyCodes = [0, 56, 55] // a, leftshift, leftmeta
            return vm
        }(),
        uiState: LiveKeyboardOverlayUIState(),
        inspectorWidth: 240,
        isMapperAvailable: false,
        kanataViewModel: nil
    )
    .padding(40)
    .frame(width: 700, height: 350)
    .background(Color(white: 0.3))
}

#Preview("No Keys") {
    LiveKeyboardOverlayView(
        viewModel: KeyboardVisualizationViewModel(),
        uiState: LiveKeyboardOverlayUIState(),
        inspectorWidth: 240,
        isMapperAvailable: false,
        kanataViewModel: nil
    )
    .padding(40)
    .frame(width: 700, height: 350)
    .background(Color(white: 0.3))
}

// MARK: - Mouse move monitor (resets idle on movement/scroll within overlay)

struct MouseMoveMonitor: NSViewRepresentable {
    let onMove: () -> Void

    func makeNSView(context _: Context) -> TrackingView {
        TrackingView(onMove: onMove)
    }

    func updateNSView(_ nsView: TrackingView, context _: Context) {
        nsView.onMove = onMove
    }

    /// NSView subclass that fires on every mouse move or scroll within its bounds.
    @MainActor
    final class TrackingView: NSView {
        var onMove: () -> Void
        private var trackingArea: NSTrackingArea?
        private var scrollMonitor: Any?

        init(onMove: @escaping () -> Void) {
            self.onMove = onMove
            super.init(frame: .zero)
        }

        @MainActor required init?(coder: NSCoder) {
            onMove = {}
            super.init(coder: coder)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let options: NSTrackingArea.Options = [.mouseMoved, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag, .mouseEnteredAndExited]
            let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            addTrackingArea(area)
            trackingArea = area
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.acceptsMouseMovedEvents = true

            // Set up local event monitor for scroll wheel events
            // This catches scroll events anywhere in the window (including the drawer)
            if scrollMonitor == nil {
                scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                    // Check if the scroll event is within our window
                    if event.window == self?.window {
                        self?.onMove()
                    }
                    return event
                }
            }
        }

        override func removeFromSuperview() {
            // Clean up scroll monitor when view is removed
            if let monitor = scrollMonitor {
                NSEvent.removeMonitor(monitor)
                scrollMonitor = nil
            }
            super.removeFromSuperview()
        }

        override func mouseMoved(with _: NSEvent) {
            onMove()
        }

        override func mouseEntered(with _: NSEvent) {
            onMove()
        }

        override func mouseExited(with _: NSEvent) {
            onMove()
        }

        override func hitTest(_: NSPoint) -> NSView? {
            // Let events pass through to the SwiftUI content while still receiving mouseMoved.
            nil
        }
    }
}

// MARK: - Tap-Hold Mini Keycap

/// Small keycap for tap-hold configuration in the customize panel
private struct TapHoldMiniKeycap: View {
    let label: String
    let isRecording: Bool
    let onTap: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    private let size: CGFloat = 48
    private let cornerRadius: CGFloat = 8
    private let fontSize: CGFloat = 16

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(backgroundColor)
                .shadow(color: shadowColor, radius: shadowRadius, y: shadowOffset)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(borderColor, lineWidth: isRecording ? 2 : 1)
                )

            if isRecording {
                Text("...")
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(foregroundColor)
            } else if label.isEmpty {
                Image(systemName: "plus")
                    .font(.system(size: fontSize * 0.7, weight: .light))
                    .foregroundStyle(foregroundColor.opacity(0.4))
            } else {
                Text(label)
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(foregroundColor)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.15, dampingFraction: 0.6), value: isPressed)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.1, dampingFraction: 0.8)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.1, dampingFraction: 0.8)) {
                    isPressed = false
                }
            }
            onTap()
        }
    }

    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool {
        colorScheme == .dark
    }

    private var foregroundColor: Color {
        isDark
            ? Color(red: 0.88, green: 0.93, blue: 1.0).opacity(isPressed ? 1.0 : 0.88)
            : Color.primary.opacity(isPressed ? 1.0 : 0.88)
    }

    private var backgroundColor: Color {
        if isRecording {
            Color.accentColor
        } else if isHovered {
            isDark ? Color(white: 0.18) : Color(white: 0.92)
        } else {
            isDark ? Color(white: 0.12) : Color(white: 0.96)
        }
    }

    private var borderColor: Color {
        if isRecording {
            Color.accentColor.opacity(0.8)
        } else if isHovered {
            isDark ? Color.white.opacity(0.3) : Color.black.opacity(0.15)
        } else {
            isDark ? Color.white.opacity(0.15) : Color.black.opacity(0.1)
        }
    }

    private var shadowColor: Color {
        isDark ? Color.black.opacity(0.5) : Color.black.opacity(0.15)
    }

    private var shadowRadius: CGFloat {
        isPressed ? 1 : 2
    }

    private var shadowOffset: CGFloat {
        isPressed ? 1 : 2
    }
}
