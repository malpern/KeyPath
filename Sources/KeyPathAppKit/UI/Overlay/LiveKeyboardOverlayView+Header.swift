import AppKit
import KeyPathCore
import SwiftUI

// MARK: - Overlay Drag Header + Inspector

/// Subtle dimpled texture to indicate the draggable header area.
/// Uses a dot pattern that suggests "grip" without affecting readability.
private struct DragHandleTexture: View {
    let isDark: Bool

    var body: some View {
        Canvas { context, size in
            let dotSpacing: CGFloat = 4
            let dotRadius: CGFloat = 0.5
            // Subtle opacity that doesn't interfere with readability
            let dotColor = isDark
                ? Color.white.opacity(0.08)
                : Color.black.opacity(0.06)

            // Draw dots in a grid pattern
            var y: CGFloat = dotSpacing / 2
            while y < size.height {
                var x: CGFloat = dotSpacing / 2
                while x < size.width {
                    let rect = CGRect(
                        x: x - dotRadius,
                        y: y - dotRadius,
                        width: dotRadius * 2,
                        height: dotRadius * 2
                    )
                    context.fill(Circle().path(in: rect), with: .color(dotColor))
                    x += dotSpacing
                }
                y += dotSpacing
            }
        }
        .allowsHitTesting(false) // Ensure drag texture doesn't block header drag gestures
    }
}

/// A tooltip modifier that uses a separate floating window (avoids clipping issues)
private struct WindowTooltip: ViewModifier {
    let text: String
    let id: String

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onHover { hovering in
                            if hovering {
                                // Convert local frame to screen coordinates
                                if let window = NSApp.windows.first(where: { $0.isVisible && $0.level == .floating }) {
                                    let localFrame = geo.frame(in: .global)
                                    let windowFrame = window.frame
                                    let screenRect = NSRect(
                                        x: windowFrame.origin.x + localFrame.origin.x,
                                        y: windowFrame.origin.y + windowFrame.height - localFrame.origin.y - localFrame.height,
                                        width: localFrame.width,
                                        height: localFrame.height
                                    )
                                    TooltipWindowController.shared.show(text: text, id: id, anchorRect: screenRect)
                                }
                            } else {
                                TooltipWindowController.shared.dismiss(id: id)
                            }
                        }
                }
            )
    }
}

private extension View {
    func windowTooltip(_ text: String, id: String) -> some View {
        modifier(WindowTooltip(text: text, id: id))
    }
}

struct OverlayDragHeader: View {
    let isDark: Bool
    let fadeAmount: CGFloat
    let height: CGFloat
    let inspectorWidth: CGFloat
    let reduceTransparency: Bool
    let isInspectorOpen: Bool
    @Binding var isDragging: Bool
    /// Whether mouse is hovering over a clickable button (for cursor)
    @Binding var isHoveringButton: Bool
    /// Japanese input mode indicator (あ/ア/A) - nil when not in Japanese mode
    let inputModeIndicator: String?
    /// Current layer name from Kanata
    let currentLayerName: String
    /// Whether launcher mode is active (drawer open with Quick Launch selected)
    let isLauncherMode: Bool
    /// Whether Kanata TCP server is connected (receiving events)
    let isKanataConnected: Bool
    /// Current system health indicator state
    let healthIndicatorState: HealthIndicatorState
    /// Whether the drawer button should be visually highlighted (hotkey feedback)
    let drawerButtonHighlighted: Bool
    let onClose: () -> Void
    let onToggleInspector: () -> Void
    /// Callback when health indicator is tapped (to launch wizard)
    let onHealthTap: () -> Void
    /// Callback when a layer is selected in the picker
    let onLayerSelected: (String) -> Void
    /// Callback when a new layer is created
    var onCreateLayer: ((String) -> Void)?
    /// Callback when a layer is deleted
    var onDeleteLayer: ((String) -> Void)?

    @State private var initialFrame: NSRect = .zero
    @State private var initialMouseLocation: NSPoint = .zero
    @State private var isLayerPickerOpen = false
    @State private var availableLayers: [String] = ["base", "nav"]
    /// Whether the layer pill is expanded (showing name) or collapsed (icon only)
    @State private var isLayerPillExpanded = true
    /// Whether mouse is hovering over the layer pill
    @State private var isHoveringLayerPill = false
    /// Timer to auto-collapse the layer pill after showing layer name
    @State private var layerCollapseTimer: Timer?
    /// Timer for grace period after mouse leaves before starting collapse
    @State private var layerGracePeriodTimer: Timer?
    /// Tracks the last layer name to detect changes
    @State private var lastLayerName: String = ""
    /// Whether the new layer sheet is showing
    @State private var showingNewLayerSheet = false
    /// New layer name being entered
    @State private var newLayerName = ""
    /// Layer being hovered for delete button
    @State private var hoveredLayer: String?
    /// Computed arrow edge for layer picker (up by default, down near screen top)
    @State private var layerPickerArrowEdge: Edge = .top

    /// System layers that cannot be deleted
    private static let systemLayers: Set<String> = ["base", "nav", "navigation", "launcher"]

    /// Check if a layer is a system layer (cannot be deleted)
    private func isSystemLayer(_ layer: String) -> Bool {
        Self.systemLayers.contains(layer.lowercased())
    }

    // MARK: - Layer Pill Timing Constants

    private let layerPillInitialCollapseDelay: TimeInterval = 2.0
    private let layerPillHoverCollapseDelay: TimeInterval = 10.0
    private let layerPillGracePeriod: TimeInterval = 0.4

    private var layerDisplayName: String {
        if isLauncherMode { return "Launcher" }
        return currentLayerName.lowercased() == "base" ? "Base" : currentLayerName.capitalized
    }

    /// Whether we're in a non-base layer (including launcher mode)
    private var isNonBaseLayer: Bool {
        isLauncherMode || currentLayerName.lowercased() != "base"
    }

    /// Whether to show the layer/Japanese input indicators (hidden until health is good)
    private var shouldShowStatusIndicators: Bool {
        healthIndicatorState == .dismissed
    }

    var body: some View {
        let buttonSize = max(10, height * 0.9)
        let indicatorCornerRadius: CGFloat = 4

        HStack(spacing: 0) {
            // Flexible spacer pushes controls to the trailing edge
            Spacer()

            // Controls aligned to the right side of the header
            // Order: Status indicators (left) → Drawer → Close (far right)
            HStack(spacing: 6) {
                // 1. Status slot (leftmost of the right-aligned group):
                // - Shows health indicator when not dismissed (including the "Ready" pill)
                // - Otherwise shows Japanese input + layer pill
                statusSlot(indicatorCornerRadius: indicatorCornerRadius, buttonSize: buttonSize)

                // 2. Toggle inspector/drawer button
                Button {
                    AppLogger.shared.log("🔘 [Header] Toggle drawer button clicked - isInspectorOpen=\(isInspectorOpen)")
                    onToggleInspector()
                } label: {
                    Image(systemName: isInspectorOpen ? "xmark.circle" : "slider.horizontal.3")
                        .font(.system(size: buttonSize * 0.6, weight: .semibold))
                        .foregroundStyle(drawerButtonHighlighted ? Color.accentColor : headerIconColor)
                        .frame(width: buttonSize, height: buttonSize)
                        .scaleEffect(drawerButtonHighlighted ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 0.1), value: drawerButtonHighlighted)
                }
                .modifier(OverlayGlassButtonStyleModifier(reduceTransparency: reduceTransparency))
                .onHover { isHoveringButton = $0 }
                .windowTooltip(isInspectorOpen ? "Close Settings" : "Open Settings", id: "drawer")
                .accessibilityIdentifier("overlay-drawer-toggle")
                .accessibilityLabel(isInspectorOpen ? "Close settings drawer" : "Open settings drawer")

                // 3. Hide button (rightmost) - hides overlay, use ⌘⌥K to bring back
                Button {
                    AppLogger.shared.log("🔘 [Header] Hide button clicked")
                    print("🔘 [Header] Hide button clicked")
                    onClose()
                } label: {
                    Image(systemName: "eye.slash")
                        .font(.system(size: buttonSize * 0.6, weight: .semibold))
                        .foregroundStyle(headerIconColor)
                        .frame(width: buttonSize, height: buttonSize)
                }
                .modifier(OverlayGlassButtonStyleModifier(reduceTransparency: reduceTransparency))
                .onHover { isHoveringButton = $0 }
                .windowTooltip("Hide Overlay (⌘⌥K)", id: "hide")
                .accessibilityIdentifier("overlay-hide-button")
                .accessibilityLabel("Hide keyboard overlay")
            }
            .padding(.trailing, 6)
            .animation(.easeOut(duration: 0.12), value: currentLayerName)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: healthIndicatorState)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .frame(height: height)
        .clipped()
        .background(DragHandleTexture(isDark: isDark))
        .contentShape(Rectangle())
        // Use simultaneousGesture so child buttons can still receive taps
        // Increased minimumDistance to 5 to distinguish taps from drags
        .simultaneousGesture(
            DragGesture(minimumDistance: 5, coordinateSpace: .global)
                .onChanged { _ in
                    if !isDragging {
                        if let window = findOverlayWindow() {
                            initialFrame = window.frame
                            initialMouseLocation = NSEvent.mouseLocation
                        }
                        isDragging = true
                    }
                    let currentMouse = NSEvent.mouseLocation
                    let deltaX = currentMouse.x - initialMouseLocation.x
                    let deltaY = currentMouse.y - initialMouseLocation.y
                    moveWindow(deltaX: deltaX, deltaY: deltaY)
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
        .onAppear {
            refreshAvailableLayers()
        }
        .onReceive(NotificationCenter.default.publisher(for: .ruleCollectionsChanged)) { _ in
            refreshAvailableLayers()
        }
        .onChange(of: isInspectorOpen) { _, _ in
            // Dismiss tooltips when drawer opens/closes so they don't get stuck
            // in their old position during animation
            TooltipWindowController.shared.dismissImmediately()
        }
    }

    /// Refresh available layers from rule collections
    private func refreshAvailableLayers() {
        Task {
            let collections = await RuleCollectionStore.shared.loadCollections()
            var layers = Set<String>(["base", "nav"])

            // Add layers from enabled rule collections
            for collection in collections where collection.isEnabled {
                // Add the collection's target layer
                layers.insert(collection.targetLayer.kanataName)

                // Also add layer from momentary activator if present
                if let activator = collection.momentaryActivator {
                    layers.insert(activator.targetLayer.kanataName)
                }
            }

            // Also include current layer if not in list (e.g., from TCP)
            layers.insert(currentLayerName.lowercased())

            await MainActor.run {
                availableLayers = layers.sorted { a, b in
                    // Base always first, then alphabetical
                    if a == "base" { return true }
                    if b == "base" { return false }
                    return a < b
                }
            }
        }
    }

    private var headerTint: Color {
        headerFill
    }

    private var headerFill: Color {
        // Transparent to let the glass material show through
        Color.clear
    }

    private var headerIconColor: Color {
        Color.white.opacity(isDark ? 0.7 : 0.6)
    }

    private func statusSlot(indicatorCornerRadius: CGFloat, buttonSize: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            if healthIndicatorState != .dismissed {
                SystemHealthIndicatorView(
                    state: healthIndicatorState,
                    isDark: isDark,
                    indicatorCornerRadius: indicatorCornerRadius,
                    onTap: onHealthTap
                )
            } else {
                HStack(spacing: 6) {
                    if !isKanataConnected {
                        kanataDisconnectedPill(indicatorCornerRadius: indicatorCornerRadius)
                    }

                    if let inputModeIndicator {
                        inputModePill(
                            indicator: inputModeIndicator,
                            indicatorCornerRadius: indicatorCornerRadius
                        )
                    }

                    // Always show layer indicator (including base layer)
                    layerPill(
                        layerDisplayName: layerDisplayName,
                        indicatorCornerRadius: indicatorCornerRadius,
                        buttonSize: buttonSize
                    )
                    .id(layerDisplayName) // Force new view when layer changes
                    .transition(.move(edge: .top))
                    .animation(.easeOut(duration: 0.2), value: layerDisplayName)
                }
                .transition(.opacity)
            }
        }
        // Don't expand to fill space - let Nav pill stay close to drawer button
        .fixedSize(horizontal: true, vertical: false)
    }

    private func inputModePill(indicator: String, indicatorCornerRadius: CGFloat) -> some View {
        let modeName = switch indicator {
        case "あ": "Hiragana"
        case "ア": "Katakana"
        case "A": "Alphanumeric"
        default: "Japanese"
        }

        return Text(indicator)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(headerIconColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: indicatorCornerRadius)
                    .fill(Color.white.opacity(isDark ? 0.1 : 0.15))
            )
            .help("Japanese Input Mode: \(modeName)")
            .accessibilityIdentifier("overlay-input-mode-indicator")
            .accessibilityLabel("Japanese input mode: \(modeName)")
    }

    /// Whether the layer pill should show the full name (expanded state, hovering, or picker open)
    private var shouldShowLayerName: Bool {
        isLayerPillExpanded || isHoveringLayerPill || isLayerPickerOpen
    }

    /// Background opacity for layer pill - brightens slightly on hover
    private var layerPillBackgroundOpacity: Double {
        let baseOpacity = isDark ? 0.1 : 0.15
        return isHoveringLayerPill ? baseOpacity + 0.08 : baseOpacity
    }

    /// Spring animation for smooth layer pill transitions
    private var layerPillSpring: Animation {
        .spring(response: 0.35, dampingFraction: 0.8)
    }

    @ViewBuilder
    private func layerPill(layerDisplayName: String, indicatorCornerRadius: CGFloat, buttonSize: CGFloat) -> some View {
        let iconName = layerIconName(for: layerDisplayName)

        Group {
            if shouldShowLayerName {
                // Expanded: pill style with name, using glass effect
                Button {
                    toggleLayerMenu()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: iconName)
                            .font(.system(size: 10, weight: .medium))
                        Text(layerDisplayName)
                            .font(.system(size: 9, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .semibold))
                            .opacity(0.7)
                    }
                    .foregroundStyle(headerIconColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .modifier(OverlayGlassEffectModifier(
                        isEnabled: !reduceTransparency,
                        cornerRadius: indicatorCornerRadius,
                        fallbackFill: Color.white.opacity(layerPillBackgroundOpacity)
                    ))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("overlay-layer-picker-toggle")
            } else {
                // Collapsed: icon-only, matches other header buttons exactly
                Button {
                    toggleLayerMenu()
                } label: {
                    Image(systemName: iconName)
                        .font(.system(size: buttonSize * 0.6, weight: .semibold))
                        .foregroundStyle(headerIconColor)
                        .frame(width: buttonSize, height: buttonSize)
                }
                .modifier(OverlayGlassButtonStyleModifier(reduceTransparency: reduceTransparency))
                .accessibilityIdentifier("overlay-layer-picker-toggle")
            }
        }
        .animation(layerPillSpring, value: shouldShowLayerName)
        .animation(.easeInOut(duration: 0.15), value: isHoveringLayerPill)
        // Extend hit area by 4px on all sides for easier targeting
        .padding(4)
        .contentShape(Rectangle())
        .padding(-4)
        .onHover { hovering in
            handleLayerPillHover(hovering)
        }
        .popover(isPresented: $isLayerPickerOpen, arrowEdge: layerPickerArrowEdge) {
            layerPickerPopover
        }
        .sheet(isPresented: $showingNewLayerSheet) {
            NewLayerSheet(
                layerName: $newLayerName,
                existingLayers: availableLayers,
                onSubmit: { name in
                    onCreateLayer?(name)
                    newLayerName = ""
                    showingNewLayerSheet = false
                },
                onCancel: {
                    newLayerName = ""
                    showingNewLayerSheet = false
                }
            )
        }
        .onChange(of: currentLayerName) { _, newValue in
            handleLayerNameChange(newValue)
        }
        .onAppear {
            // Initialize lastLayerName and start initial collapse timer
            lastLayerName = currentLayerName
            scheduleLayerPillCollapse(delay: layerPillInitialCollapseDelay)
        }
        .help("Current layer: \(layerDisplayName). Click to see available layers.")
        .accessibilityIdentifier("overlay-layer-indicator")
        .accessibilityLabel("Current layer: \(layerDisplayName). Click to see available layers.")
    }

    /// Handle hover state changes with grace period
    private func handleLayerPillHover(_ hovering: Bool) {
        // Cancel any pending grace period timer
        layerGracePeriodTimer?.invalidate()
        layerGracePeriodTimer = nil

        if hovering {
            // Mouse entered - cancel collapse and expand immediately
            layerCollapseTimer?.invalidate()
            isHoveringLayerPill = true

            // If collapsed, expand with animation
            if !isLayerPillExpanded {
                withAnimation(layerPillSpring) {
                    isLayerPillExpanded = true
                }
            }
        } else {
            // Mouse left - start grace period before actually marking as not hovering
            layerGracePeriodTimer = Timer.scheduledTimer(withTimeInterval: layerPillGracePeriod, repeats: false) { _ in
                DispatchQueue.main.async {
                    isHoveringLayerPill = false
                    // Schedule collapse with longer delay since user was engaged
                    scheduleLayerPillCollapse(delay: layerPillHoverCollapseDelay)
                }
            }
        }
    }

    /// Handle layer name changes - expand the pill and schedule collapse
    private func handleLayerNameChange(_ newLayerName: String) {
        // Only expand if layer actually changed
        guard newLayerName != lastLayerName else { return }
        lastLayerName = newLayerName

        // Cancel any timers
        layerCollapseTimer?.invalidate()
        layerGracePeriodTimer?.invalidate()

        // Expand the pill to show the new layer name
        withAnimation(layerPillSpring) {
            isLayerPillExpanded = true
        }

        // Schedule collapse after showing the name (use initial delay for layer changes)
        scheduleLayerPillCollapse(delay: layerPillInitialCollapseDelay)
    }

    /// Schedule the layer pill to collapse after a delay
    private func scheduleLayerPillCollapse(delay: TimeInterval) {
        // Cancel any existing timer
        layerCollapseTimer?.invalidate()

        // Schedule collapse
        layerCollapseTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            DispatchQueue.main.async {
                // Don't collapse if hovering or picker is open
                guard !isHoveringLayerPill, !isLayerPickerOpen else { return }
                withAnimation(layerPillSpring) {
                    isLayerPillExpanded = false
                }
            }
        }
    }

    /// Toggle layer picker with smart positioning (opens up by default, down near screen top)
    private func toggleLayerMenu() {
        if isLayerPickerOpen {
            // Closing - just toggle
            isLayerPickerOpen = false
        } else {
            // Opening - compute arrow edge first
            layerPickerArrowEdge = computeLayerPickerArrowEdge()
            isLayerPickerOpen = true
        }
    }

    /// Compute which edge the popover arrow should point from based on available screen space
    private func computeLayerPickerArrowEdge() -> Edge {
        guard let window = findOverlayWindow(),
              let screen = window.screen ?? NSScreen.main
        else {
            return .top // Default to opening upward
        }

        let windowTop = window.frame.maxY
        let screenTop = screen.visibleFrame.maxY
        let spaceAbove = screenTop - windowTop

        // Estimate popover height (layers + new layer option + padding)
        // Each row is ~40pt, header/footer ~12pt
        let estimatedRowHeight: CGFloat = 40
        let estimatedPopoverHeight = CGFloat(availableLayers.count + 1) * estimatedRowHeight + 24

        // If not enough space above, open downward (arrowEdge: .bottom)
        // Add some margin (20pt) for safety
        if spaceAbove < estimatedPopoverHeight + 20 {
            return .bottom
        }

        return .top
    }

    /// Popover showing available layers
    private var layerPickerPopover: some View {
        VStack(spacing: 0) {
            ForEach(Array(availableLayers.enumerated()), id: \.element) { index, layer in
                layerPickerRow(layer: layer, index: index)

                if index < availableLayers.count - 1 {
                    Divider()
                        .opacity(0.2)
                        .padding(.horizontal, 8)
                }
            }

            Divider()
                .opacity(0.2)
                .padding(.horizontal, 8)

            // New Layer option - styled same as layer rows
            Button {
                isLayerPickerOpen = false
                showingNewLayerSheet = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.body)
                        .frame(width: 20)
                        .foregroundStyle(.secondary)
                    Text("New Layer...")
                        .font(.body)
                    Spacer()
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(LayerPickerButtonStyle())
            .focusable(false)
            .accessibilityIdentifier("layer-picker-new")
        }
        .padding(.vertical, 6)
        .frame(minWidth: 200)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
        )
        .padding(4)
    }

    /// Individual layer row in the picker
    @ViewBuilder
    private func layerPickerRow(layer: String, index _: Int) -> some View {
        let displayName = layer.lowercased() == "base" ? "Base" : layer.capitalized
        let isCurrentLayer = currentLayerName.lowercased() == layer.lowercased()
        let layerIcon = layerIconName(for: displayName)
        let canDelete = !isSystemLayer(layer)
        let isHovered = hoveredLayer == layer

        HStack(spacing: 0) {
            Button {
                isLayerPickerOpen = false
                onLayerSelected(layer)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: layerIcon)
                        .font(.body)
                        .frame(width: 20)
                        .foregroundStyle(isCurrentLayer ? Color.accentColor : .secondary)
                    Text(displayName)
                        .font(.body)
                    Spacer()
                    if isCurrentLayer {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(LayerPickerButtonStyle())
            .focusable(false)

            // Delete button for user-created layers (hover only)
            if canDelete {
                Button {
                    isLayerPickerOpen = false
                    onDeleteLayer?(layer)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .opacity(isHovered ? 1 : 0)
                .accessibilityIdentifier("layer-delete-\(layer)")
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(isCurrentLayer ? 0.05 : (isHovered ? 0.03 : 0)))
        )
        .onHover { hovering in
            hoveredLayer = hovering ? layer : nil
        }
    }

    /// Button style for layer picker items (no focus ring)
    private struct LayerPickerButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.08 : 0))
                )
        }
    }

    private func layerIconName(for layerDisplayName: String) -> String {
        let lower = layerDisplayName.lowercased()

        switch lower {
        case "base":
            return "keyboard"
        case "nav", "navigation", "vim":
            return "arrow.up.and.down.and.arrow.left.and.right"
        case "window", "window-mgmt":
            return "macwindow"
        case "numpad", "num":
            return "number"
        case "sym", "symbol":
            return "character"
        case "launcher", "quick launcher":
            return "app.badge"
        default:
            return "square.3.layers.3d"
        }
    }

    private func kanataDisconnectedPill(indicatorCornerRadius: CGFloat) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 9, weight: .medium))
            Text("No TCP")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(Color.orange.opacity(0.9))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: indicatorCornerRadius)
                .fill(Color.orange.opacity(isDark ? 0.15 : 0.2))
        )
        .help("Not receiving events from Kanata")
        .accessibilityIdentifier("overlay-kanata-disconnected-indicator")
        .accessibilityLabel("Not connected to Kanata TCP server")
    }

    private func moveWindow(deltaX: CGFloat, deltaY: CGFloat) {
        guard let window = findOverlayWindow() else { return }
        var newOrigin = initialFrame.origin
        newOrigin.x += deltaX
        newOrigin.y += deltaY
        window.setFrameOrigin(newOrigin)
    }

    private func findOverlayWindow() -> NSWindow? {
        NSApplication.shared.windows.first {
            $0.styleMask.contains(.borderless) && $0.level == .floating
        }
    }
}

// MARK: - System Health Indicator View

/// Displays system health status in the overlay header.
/// Shows spinner during checking, green check when healthy, orange warning when unhealthy.
struct SystemHealthIndicatorView: View {
    let state: HealthIndicatorState
    let isDark: Bool
    let indicatorCornerRadius: CGFloat
    let onTap: () -> Void

    private var headerIconColor: Color {
        Color.white.opacity(isDark ? 0.7 : 0.6)
    }

    var body: some View {
        Group {
            switch state {
            case .checking:
                // Spinner while health is being calculated
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                    Text("Checking...")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(headerIconColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: indicatorCornerRadius)
                        .fill(Color.white.opacity(isDark ? 0.1 : 0.15))
                )

            case .healthy:
                // Green checkmark - briefly visible before fading
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.green)
                    Text("Ready")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(headerIconColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: indicatorCornerRadius)
                        .fill(Color.green.opacity(0.15))
                )
                .transition(.opacity.combined(with: .scale))

            case let .unhealthy(issueCount):
                // Orange warning - clickable to launch wizard
                Button {
                    AppLogger.shared.log("🔘 [Health] Issues button tapped - launching wizard")
                    onTap()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.orange)
                        Text(issueCount == 1 ? "1 Issue" : "\(issueCount) Issues")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: indicatorCornerRadius)
                            .fill(Color.orange.opacity(0.2))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: indicatorCornerRadius)
                            .stroke(Color.orange.opacity(0.4), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .highPriorityGesture(TapGesture().onEnded {
                    AppLogger.shared.log("🔘 [Health] Issues button tap gesture - launching wizard")
                    onTap()
                })
                .help("Click to fix system issues")
                .accessibilityIdentifier("overlay-health-indicator-error")
                .accessibilityLabel("System has \(issueCount) issue\(issueCount == 1 ? "" : "s"). Click to fix.")
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.8).combined(with: .opacity),
                    removal: .opacity
                ))

            case .dismissed:
                EmptyView()
            }
        }
        .accessibilityIdentifier("overlay-health-indicator")
    }
}
