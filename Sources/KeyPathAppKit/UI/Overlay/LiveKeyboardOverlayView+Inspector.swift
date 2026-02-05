import AppKit
import KeyPathCore
import SwiftUI

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

    @AppStorage(KeymapPreferences.keymapIdKey) var selectedKeymapId: String = LogicalKeymap.defaultId
    @AppStorage(KeymapPreferences.includePunctuationStoreKey) var includePunctuationStore: String = "{}"
    @AppStorage(LayoutPreferences.layoutIdKey) var selectedLayoutId: String = LayoutPreferences.defaultLayoutId
    @AppStorage("overlayColorwayId") var selectedColorwayId: String = GMKColorway.default.id

    /// Category to scroll to in physical layout grid
    @State var scrollToLayoutCategory: LayoutCategory?

    /// Which slide-over panel is currently open (nil = none)
    @State var activeDrawerPanel: DrawerPanel?

    // MARK: - Tap & Hold Panel State (Apple-style 80/20 design)

    /// Key label being configured in the Tap & Hold panel
    @State var tapHoldKeyLabel: String = "A"
    /// Key code being configured
    @State var tapHoldKeyCode: UInt16? = 0
    /// Initially selected behavior slot when panel opens
    @State var tapHoldInitialSlot: BehaviorSlot = .tap
    /// Tap behavior action
    @State var tapHoldTapAction: BehaviorAction = .key("a")
    /// Hold behavior action
    @State var tapHoldHoldAction: BehaviorAction = .none
    /// Double tap behavior action
    /// Tap + Hold behavior action
    @State var tapHoldComboAction: BehaviorAction = .none
    /// Responsiveness level (maps to timing thresholds)
    @State var tapHoldResponsiveness: ResponsivenessLevel = .balanced
    /// Use tap immediately when typing starts
    @State var tapHoldUseTapImmediately: Bool = true

    // MARK: - Legacy Customize Panel State (deprecated - use Tap & Hold panel)

    /// Hold action for tap-hold configuration
    @State var customizeHoldAction: String = ""
    /// Double tap action
    @State var customizeDoubleTapAction: String = ""
    /// Additional tap-dance steps (Triple Tap, Quad Tap, etc.)
    @State var customizeTapDanceSteps: [(label: String, action: String)] = []
    /// Tap timeout in milliseconds
    @State var customizeTapTimeout: Int = 200
    /// Hold timeout in milliseconds
    @State var customizeHoldTimeout: Int = 200
    /// Whether to show separate tap/hold timing fields
    @State var customizeShowTimingAdvanced: Bool = false
    /// Which field is currently recording (nil = none)
    @State var customizeRecordingField: String?
    /// Local event monitor for key capture
    @State var customizeKeyMonitor: Any?

    // MARK: - Launcher Customize Panel State

    /// Current launcher activation mode
    @State var launcherActivationMode: LauncherActivationMode = .holdHyper
    /// Current hyper trigger mode (hold vs tap)
    @State var launcherHyperTriggerMode: HyperTriggerMode = .hold
    /// Whether browser history sheet is showing
    @State var showLauncherHistorySuggestions = false
    /// Existing launcher domains (for history import)
    @State var launcherExistingDomains: Set<String> = []

    /// Labels for tap-dance steps beyond double tap
    static let tapDanceLabels = ["Triple Tap", "Quad Tap", "Quint Tap"]

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

    var isDark: Bool {
        colorScheme == .dark
    }

    func unavailableSection(title: String, message: String) -> some View {
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
