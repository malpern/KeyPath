import AppKit
import KeyPathCore
import KeyPathWizardCore
import SwiftUI

/// Simplified system status overview component for the summary page
struct WizardSystemStatusOverview: View {
    let systemState: WizardSystemState
    let issues: [WizardIssue]
    let stateInterpreter: WizardStateInterpreter
    let onNavigateToPage: ((WizardPage) -> Void)?
    // Authoritative signal for service status - ensures consistency with detail page
    let kanataIsRunning: Bool
    /// When false, show only items that need attention (failed). When true, show all.
    let showAllItems: Bool
    /// Ordered navigation sequence, synced to current display filter
    @Binding var navSequence: [WizardPage]
    /// Number of visible items that are not completed (used by summary header)
    @Binding var visibleIssueCount: Int

    @State private var scrollOffset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var containerHeight: CGFloat = 0
    @State private var duplicateCopies: [String] = []
    // Cache heavy probes so SwiftUI re-renders don’t hammer the filesystem/network
    private static var cache = ProbeCache()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: WizardDesign.Spacing.labelGap) {
                ForEach(displayItems, id: \.id) { item in
                    // Row with subtle hover effect
                    HoverableRow(
                        isNavigable: item.isNavigable,
                        onTap: item.isNavigable ? { onNavigateToPage?(item.targetPage) } : nil
                    ) {
                        VStack(alignment: .leading, spacing: 0) {
                            WizardStatusItem(
                                icon: item.icon,
                                title: item.title,
                                subtitle: item.subtitle,
                                status: item.status,
                                isNavigable: item.isNavigable,
                                action: nil, // Tap handled at HoverableRow level
                                isFinalStatus: isFinalKeyPathStatus(item: item),
                                showInitialClock: shouldShowInitialClock(for: item),
                                tooltip: item.relatedIssues.asTooltipText()
                            )

                            // Show expanded details for failed items
                            if item.status == .failed, !item.subItems.isEmpty {
                                VStack(alignment: .leading, spacing: WizardDesign.Spacing.labelGap) {
                                    ForEach(item.subItems, id: \.id) { subItem in
                                        WizardStatusItem(
                                            icon: subItem.icon,
                                            title: subItem.title,
                                            subtitle: subItem.subtitle,
                                            status: subItem.status,
                                            isNavigable: subItem.isNavigable,
                                            action: subItem.isNavigable ? { onNavigateToPage?(subItem.targetPage) } : nil,
                                            tooltip: subItem.relatedIssues.asTooltipText()
                                        )
                                        .padding(.leading, WizardDesign.Spacing.indentation)
                                    }
                                }
                                .padding(.top, WizardDesign.Spacing.labelGap)
                            }
                        }
                    }
                    // Keep inserts/removals simple to avoid list jitter
                    .transition(.opacity)
                }
            }
            // Track content geometry to compute scroll affordance
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(
                            key: ContentGeometryKey.self,
                            value: ContentGeometry(
                                minY: proxy.frame(in: .named("WizardOverviewScroll")).minY,
                                height: proxy.size.height
                            )
                        )
                }
            )
            // Center to 50% of window width (window width is fixed by layout)
            .frame(width: WizardDesign.Layout.pageWidth * 0.5)
            .padding(.vertical, WizardDesign.Spacing.sectionGap)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .coordinateSpace(name: "WizardOverviewScroll")
        .scrollIndicators(.hidden) // Hide scroll indicators to avoid visual clutter
        .focusable(false)
        .modifier(WizardDesign.DisableFocusEffects())
        .background(NoFocusRingBackground())
        .onAppear {
            // Aggressively disable focus ring on underlying NSView
            DispatchQueue.main.async {
                if let window = NSApp.keyWindow,
                   let contentView = window.contentView {
                    disableFocusRings(in: contentView)
                }
            }
        }
        // Track container height for fade logic
        .background(
            GeometryReader { proxy in
                if #available(macOS 14.0, *) {
                    Color.clear
                        .onAppear { containerHeight = proxy.size.height }
                        .onChange(of: proxy.size.height) { _, newValue in
                            containerHeight = newValue
                        }
                } else {
                    Color.clear
                        .onAppear { containerHeight = proxy.size.height }
                        .onChange(of: proxy.size.height) { newValue in
                            containerHeight = newValue
                        }
                }
            }
        )
        .onPreferenceChange(ContentGeometryKey.self) { value in
            scrollOffset = value.minY
            contentHeight = value.height
        }
        .onAppear {
            duplicateCopies = HelperMaintenance.shared.detectDuplicateAppCopies()
            updateNavSequence()
        }
        .onChange(of: showAllItems) { _, _ in updateNavSequence() }
        .onChange(of: issues.count) { _, _ in updateNavSequence() }
        .onChange(of: systemState) { _, _ in updateNavSequence() }
        .overlay(alignment: .top) {
            if canShowTopFade {
                LinearGradient(
                    gradient: Gradient(colors: [
                        WizardDesign.Colors.wizardBackground,
                        WizardDesign.Colors.wizardBackground.opacity(0.0)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 14)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if canShowBottomFade {
                LinearGradient(
                    gradient: Gradient(colors: [
                        WizardDesign.Colors.wizardBackground.opacity(0.0),
                        WizardDesign.Colors.wizardBackground
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 14)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.clear)
    }

    /// Recursively disable focus rings in all subviews
    private func disableFocusRings(in view: NSView) {
        view.focusRingType = .none
        for subview in view.subviews {
            disableFocusRings(in: subview)
        }
    }

    private var canShowTopFade: Bool {
        // Negative minY means scrolled down; show top fade when there is content above
        scrollOffset < -1
    }

    private var canShowBottomFade: Bool {
        // Remaining content below container?
        (contentHeight + scrollOffset) - containerHeight > 1
    }

    /// Items to render given the current toggle state
    private var displayItems: [StatusItemModel] {
        Self.filteredDisplayItems(statusItems, showAllItems: showAllItems)
    }

    // MARK: - Geometry Preference

    private struct ContentGeometry: Equatable {
        let minY: CGFloat
        let height: CGFloat
    }

    private struct ContentGeometryKey: PreferenceKey {
        static let defaultValue: ContentGeometry = .init(minY: 0, height: 0)
        static func reduce(value: inout ContentGeometry, nextValue: () -> ContentGeometry) {
            value = nextValue()
        }
    }

    // MARK: - Animation Helpers

    private func isFinalKeyPathStatus(item: StatusItemModel) -> Bool {
        // The Communication Server is the final status that should get pulse animation when completed
        item.id == "communication-server" && item.status == .completed
    }

    private func shouldShowInitialClock(for item: StatusItemModel) -> Bool {
        // Show initial clock for all items except those that are truly not started
        // This creates the "all items start checking simultaneously" effect
        item.status == .completed || item.status == .failed
    }

    // MARK: - Status Items Creation

    private var statusItems: [StatusItemModel] {
        var items: [StatusItemModel] = []

        // 1. Privileged Helper (required for system operations)
        let helperIssues = issues.filter { issue in
            if case let .component(req) = issue.identifier {
                return req == .privilegedHelper || req == .privilegedHelperUnhealthy
            }
            return false
        }
        let helperStatus: InstallationStatus = {
            if systemState == .initializing {
                return .notStarted
            }

            // Check for specific issue types to determine status color
            let hasNotInstalledIssue = helperIssues.contains { issue in
                if case let .component(req) = issue.identifier {
                    return req == .privilegedHelper
                }
                return false
            }
            let hasUnhealthyIssue = helperIssues.contains { issue in
                if case let .component(req) = issue.identifier {
                    return req == .privilegedHelperUnhealthy
                }
                return false
            }

            // RED if not installed, ORANGE if installed but unhealthy, GREEN if working
            if hasNotInstalledIssue {
                return .failed // Red - not installed
            } else if hasUnhealthyIssue {
                return .failed // Treat unhealthy/not responding as error (red)
            } else {
                return .completed // Green - installed and working
            }
        }()
        let helperSubtitle: String? = duplicateCopies.count > 1 ? "Multiple app copies detected" : nil
        items.append(
            StatusItemModel(
                id: "privileged-helper",
                icon: "shield.checkered",
                title: "Privileged Helper",
                subtitle: helperSubtitle,
                status: helperStatus,
                isNavigable: true,
                targetPage: .helper,
                relatedIssues: helperIssues
            ))

        // 3. Full Disk Access (Optional but recommended)
        let hasFullDiskAccess = checkFullDiskAccess()
        let fullDiskAccessStatus: InstallationStatus = {
            if systemState == .initializing {
                return .notStarted
            }
            return hasFullDiskAccess ? .completed : .notStarted
        }()
        items.append(
            StatusItemModel(
                id: "full-disk-access",
                icon: "folder",
                title: "Full Disk Access (Optional)",
                status: fullDiskAccessStatus,
                isNavigable: true,
                targetPage: .fullDiskAccess
            ))

        // 4. System Conflicts
        let conflictIssues = issues.filter { $0.category == .conflicts }
        let conflictStatus: InstallationStatus = {
            if systemState == .initializing {
                return .notStarted
            }
            return !conflictIssues.isEmpty ? .failed : .completed
        }()
        items.append(
            StatusItemModel(
                id: "conflicts",
                icon: "exclamationmark.triangle",
                title: "Resolve System Conflicts",
                status: conflictStatus,
                isNavigable: true,
                targetPage: .conflicts,
                relatedIssues: conflictIssues
            ))

        // 5. Input Monitoring Permission
        let inputMonitoringStatus = getInputMonitoringStatus()
        let inputMonitoringIssues = issues.filter { issue in
            if case let .permission(req) = issue.identifier {
                return req == .keyPathInputMonitoring || req == .kanataInputMonitoring
            }
            return false
        }
        items.append(
            StatusItemModel(
                id: "input-monitoring",
                icon: "eye",
                title: "Input Monitoring Permission",
                status: inputMonitoringStatus,
                isNavigable: true,
                targetPage: .inputMonitoring,
                relatedIssues: inputMonitoringIssues
            ))

        // 6. Accessibility Permission
        let accessibilityStatus = getAccessibilityStatus()
        let accessibilityIssues = issues.filter { issue in
            if case let .permission(req) = issue.identifier {
                return req == .keyPathAccessibility || req == .kanataAccessibility
            }
            return false
        }
        items.append(
            StatusItemModel(
                id: "accessibility",
                icon: "accessibility",
                title: "Accessibility",
                status: accessibilityStatus,
                isNavigable: true,
                targetPage: .accessibility,
                relatedIssues: accessibilityIssues
            ))

        // 6. Karabiner Driver Setup (led first in list for clear dependency order)
        let karabinerStatus = getKarabinerComponentsStatus()
        let karabinerIssues = issues.filter { issue in
            // Filter for installation issues related to Karabiner driver
            issue.category == .installation && issue.identifier.isVHIDRelated
        }
        items.append(
            StatusItemModel(
                id: "karabiner-components",
                icon: "keyboard.macwindow",
                title: "Karabiner Driver",
                status: karabinerStatus,
                isNavigable: true,
                targetPage: .karabinerComponents,
                relatedIssues: karabinerIssues
            ))

        // 7. Kanata Service (depends on helper + driver)
        let serviceStatus = getServiceStatus()
        let serviceNavigation = getServiceNavigationTarget()
        let serviceIssues = issues.filter { issue in
            issue.category == .daemon
        }
        items.append(
            StatusItemModel(
                id: "kanata-service",
                icon: "app.badge.checkmark",
                title: "Kanata Service",
                subtitle: serviceStatus == .failed
                    ? "Fix permissions to enable service" : (kanataIsRunning ? "Running" : nil),
                status: serviceStatus,
                isNavigable: true,
                targetPage: serviceNavigation.page,
                relatedIssues: serviceIssues
            ))

        // Check dependency requirements for remaining items
        let prerequisitesMet = shouldShowDependentItems()

        // 8. Kanata Engine Setup (hidden if Karabiner Driver not completed)
        if prerequisitesMet.showKanataEngineItem {
            let kanataComponentsStatus = getKanataComponentsStatus()
            let kanataComponentsIssues = issues.filter { issue in
                // Kanata component issues
                if case let .component(comp) = issue.identifier {
                    return comp == .kanataBinaryMissing
                }
                return false
            }
            items.append(
                StatusItemModel(
                    id: "kanata-components",
                    icon: "cpu.fill",
                    title: "Kanata Engine Setup",
                    status: kanataComponentsStatus,
                    isNavigable: true,
                    targetPage: .kanataComponents,
                    relatedIssues: kanataComponentsIssues
                ))
        }

        // 9. Communication Server (hidden if dependencies not met)
        if prerequisitesMet.showCommunicationItem {
            let commServerStatus = getCommunicationServerStatus()
            // Communication server issues (no specific category, use empty for now)
            items.append(
                StatusItemModel(
                    id: "communication-server",
                    icon: "network",
                    title: "Communication",
                    subtitle: commServerStatus == .notStarted && !kanataIsRunning
                        ? "Kanata isn't running" : nil,
                    status: commServerStatus,
                    isNavigable: true,
                    targetPage: .communication
                ))
        }

        return items
    }

    // MARK: - Navigation Sequence Sync

    private func updateNavSequence() {
        AppLogger.shared.log("🔍 [NavSeq] updateNavSequence called")
        AppLogger.shared.log("🔍 [NavSeq] displayItems count: \(displayItems.count)")
        AppLogger.shared.log("🔍 [NavSeq] showAllItems: \(showAllItems)")

        var seen = Set<WizardPage>()
        var ordered: [WizardPage] = []
        for item in displayItems {
            let page = item.targetPage
            AppLogger.shared.log("🔍 [NavSeq]   - displayItem: \(item.title) → \(page.displayName)")
            if page != .summary, !seen.contains(page) {
                seen.insert(page)
                ordered.append(page)
            }
        }
        navSequence = ordered
        visibleIssueCount = displayItems.filter { $0.status != .completed }.count
        AppLogger.shared.log(
            "🔍 [NavSeq] ✅ navSequence updated: \(ordered.count) pages: \(ordered.map(\.displayName))")
    }

    // MARK: - Dependency Logic

    private struct DependencyVisibility {
        let showKanataEngineItem: Bool
        let showCommunicationItem: Bool
    }

    // MARK: - Lightweight probe caching

    /// Keeps recent probe results so the SwiftUI body doesn't hammer disk/network on every recompute.
    private struct ProbeCache {
        private static let ttl: TimeInterval = 1.5

        private var fda: (value: Bool, ts: Date)?
        private var comm: (value: InstallationStatus, port: Int, kanataRunning: Bool, ts: Date)?

        mutating func fullDiskAccessIfFresh() -> Bool? {
            guard let fda, Date().timeIntervalSince(fda.ts) < Self.ttl else { return nil }
            return fda.value
        }

        mutating func updateFullDiskAccess(_ value: Bool) {
            fda = (value, Date())
        }

        mutating func communicationStatusIfFresh(
            port: Int,
            kanataRunning: Bool
        ) -> InstallationStatus? {
            guard let comm,
                  comm.port == port,
                  comm.kanataRunning == kanataRunning,
                  Date().timeIntervalSince(comm.ts) < Self.ttl
            else { return nil }
            return comm.value
        }

        mutating func updateCommunication(
            status: InstallationStatus,
            port: Int,
            kanataRunning: Bool
        ) {
            comm = (status, port, kanataRunning, Date())
        }
    }

    private func shouldShowDependentItems() -> DependencyVisibility {
        // Prerequisites for Kanata Engine Setup:
        // - Karabiner Driver Setup must be completed (Kanata requires VirtualHID driver)
        let karabinerDriverCompleted = getKarabinerComponentsStatus() == .completed

        // Communication item shown when Kanata is running
        return DependencyVisibility(
            showKanataEngineItem: karabinerDriverCompleted,
            showCommunicationItem: kanataIsRunning
        )
    }

    // MARK: - Dependency-aware filtering

    /// Declarative dependency map for wizard items.
    /// Keys are status item IDs used in `statusItems`.
    private var itemDependencies: [String: [String]] {
        [
            // Must have helper before anything privileged
            "kanata-service": ["privileged-helper", "karabiner-components"],
            "communication-server": ["kanata-service"],
            "kanata-components": ["karabiner-components"],
            "background-services": ["privileged-helper"],
            "karabiner-components": ["privileged-helper"]
        ]
    }

    /// Helper to see if all dependencies are satisfied (completed) given the current items.
    private func dependenciesSatisfied(
        for item: StatusItemModel,
        in allItems: [StatusItemModel]
    ) -> Bool {
        guard let deps = itemDependencies[item.id], !deps.isEmpty else { return true }
        let statusByID = Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0.status) })
        return deps.allSatisfy { statusByID[$0] == .completed }
    }

    // MARK: - Filtering helper (shared with tests)

    static func filteredDisplayItems(_ items: [StatusItemModel], showAllItems: Bool)
        -> [StatusItemModel] {
        if showAllItems { return items }
        // Show all incomplete items, even if their prerequisites are still pending; ordering is preserved.
        return items.filter { $0.status != .completed }
    }

    // MARK: - Status Helpers

    private func checkFullDiskAccess() -> Bool {
        if let cached = Self.cache.fullDiskAccessIfFresh() { return cached }

        // Check if we can read the system TCC database (requires Full Disk Access)
        // This is the most accurate test and matches WizardFullDiskAccessPage implementation
        let systemTCCPath = "/Library/Application Support/com.apple.TCC/TCC.db"

        var granted = false
        if FileManager.default.isReadableFile(atPath: systemTCCPath) {
            // Try a very light read operation
            if let data = try? Data(
                contentsOf: URL(fileURLWithPath: systemTCCPath), options: .mappedIfSafe
            ),
                !data.isEmpty {
                granted = true
            }
        }

        AppLogger.shared.log(
            granted
                ? "🔐 [WizardSystemStatusOverview] FDA granted - can read system TCC database (cached)"
                : "🔐 [WizardSystemStatusOverview] FDA not granted - cannot read system TCC database (cached)")

        Self.cache.updateFullDiskAccess(granted)
        return granted
    }

    private func getInputMonitoringStatus() -> InstallationStatus {
        // If system is still initializing, don't show completed status
        if systemState == .initializing {
            return .notStarted
        }

        let hasInputMonitoringIssues = issues.contains { issue in
            if case let .permission(permissionType) = issue.identifier {
                return permissionType == .keyPathInputMonitoring || permissionType == .kanataInputMonitoring
            }
            return false
        }
        return hasInputMonitoringIssues ? .failed : .completed
    }

    private func getAccessibilityStatus() -> InstallationStatus {
        // If system is still initializing, don't show completed status
        if systemState == .initializing {
            return .notStarted
        }

        let hasAccessibilityIssues = issues.contains { issue in
            if case let .permission(permissionType) = issue.identifier {
                return permissionType == .keyPathAccessibility || permissionType == .kanataAccessibility
            }
            return false
        }
        return hasAccessibilityIssues ? .failed : .completed
    }

    private func getKarabinerComponentsStatus() -> InstallationStatus {
        // Use centralized evaluator (single source of truth)
        KarabinerComponentsStatusEvaluator.evaluate(
            systemState: systemState,
            issues: issues
        )
    }

    private func getKanataComponentsStatus() -> InstallationStatus {
        // If system is still initializing, don't show completed status
        if systemState == .initializing {
            return .notStarted
        }

        // Check for Kanata-related issues
        let hasKanataIssues = issues.contains { issue in
            if issue.category == .installation {
                switch issue.identifier {
                case .component(.kanataBinaryMissing),
                     .component(.kanataService),
                     .component(.orphanedKanataProcess):
                    return true
                default:
                    return false
                }
            }
            return false
        }

        return hasKanataIssues ? .failed : .completed
    }

    private func getCommunicationServerStatus() -> InstallationStatus {
        // SECURITY NOTE (ADR-013): No authentication check needed
        // Kanata v1.9.0 TCP server does not support authentication.
        // We only verify: (1) plist has --port argument, (2) Kanata is running
        // This is acceptable for localhost-only IPC with config validation.

        // If system is still initializing, don't show status
        if systemState == .initializing {
            return .notStarted
        }

        // If Kanata isn't running, show as not started (empty circle)
        guard kanataIsRunning else { return .notStarted }

        // Check for communication server issues in the shared issues array first
        let hasCommServerIssues = issues.contains { issue in
            if case let .component(component) = issue.identifier {
                switch component {
                case .kanataTCPServer,
                     .communicationServerConfiguration, .communicationServerNotResponding,
                     .tcpServerConfiguration, .tcpServerNotResponding:
                    return true
                default:
                    return false
                }
            }
            return false
        }

        // If there are detected issues in the shared state, show as failed
        if hasCommServerIssues {
            return .failed
        }

        // Resolve TCP port from LaunchDaemon plist, then probe Hello/Status quickly
        // Check SMAppService plist first if active, otherwise fall back to legacy plist
        let plistPath = KanataDaemonManager.getActivePlistPath()

        guard let plistData = try? Data(contentsOf: URL(fileURLWithPath: plistPath)),
              let plist = try? PropertyListSerialization.propertyList(
                  from: plistData, options: [], format: nil
              ) as? [String: Any],
              let args = plist["ProgramArguments"] as? [String],
              let idx = args.firstIndex(of: "--port"), args.count > idx + 1,
              let port = Int(args[idx + 1].split(separator: ":").last ?? Substring(""))
        else {
            return .failed
        }

        // Fast synchronous probe to align with detail page (requires Status capability)
        if let cached = Self.cache.communicationStatusIfFresh(port: port, kanataRunning: kanataIsRunning) {
            return cached
        }

        let t0 = CFAbsoluteTimeGetCurrent()
        let ok = probeTCPHelloRequiresStatus(port: port, timeoutMs: 300)
        let dt = CFAbsoluteTimeGetCurrent() - t0
        AppLogger.shared.log(
            "🌐 [WizardCommSummary] probe result: ok=\(ok) port=\(port) duration_ms=\(Int(dt * 1000))")

        let status: InstallationStatus = ok ? .completed : .failed
        Self.cache.updateCommunication(status: status, port: port, kanataRunning: kanataIsRunning)
        return status
    }

    func getServiceStatus() -> InstallationStatus {
        // If system is still initializing, show as in progress
        if systemState == .initializing {
            return .inProgress
        }

        // Live signal: if Kanata is currently running, treat service as healthy even
        // if a stale issue snapshot still contains daemon issues.
        if kanataIsRunning {
            return .completed
        }

        // Check for service-related issues (daemon category)
        // This includes both Kanata Service and Karabiner Daemon
        let hasServiceIssues = issues.contains { issue in
            issue.category == .daemon
        }

        // If there are service issues, show as failed (red X)
        if hasServiceIssues {
            return .failed
        }

        // Otherwise, show as not started (empty circle)
        // This happens during initial setup before user clicks "Start Service"
        return .notStarted
    }

    private func getServiceNavigationTarget() -> (page: WizardPage, reason: String) {
        // When service fails, navigate to the most critical missing permission
        let hasInputMonitoringIssues = issues.contains { issue in
            if case let .permission(permission) = issue.identifier {
                return permission == .kanataInputMonitoring
            }
            return false
        }

        let hasAccessibilityIssues = issues.contains { issue in
            if case let .permission(permission) = issue.identifier {
                return permission == .kanataAccessibility
            }
            return false
        }

        // Navigate to the first blocking permission page
        if hasInputMonitoringIssues {
            return (.inputMonitoring, "Input Monitoring permission required")
        } else if hasAccessibilityIssues {
            return (.accessibility, "Accessibility permission required")
        } else {
            // Default to service page if no specific permission issue
            return (.service, "Check service status")
        }
    }
}

// MARK: - Hoverable Row Wrapper

private struct HoverableRow<Content: View>: View {
    @State private var hovering = false
    let isNavigable: Bool
    let onTap: (() -> Void)?
    let content: () -> Content

    init(
        isNavigable: Bool = false,
        onTap: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isNavigable = isNavigable
        self.onTap = onTap
        self.content = content
    }

    var body: some View {
        content()
            .padding(.vertical, WizardDesign.Spacing.labelGap)
            .padding(.horizontal, WizardDesign.Spacing.cardPadding)
            .contentShape(Rectangle())
            .overlay(alignment: .center) {
                // 1px horizontal inset so the hover background doesn't touch edges
                RoundedRectangle(cornerRadius: 8)
                    .fill(hovering ? Color.primary.opacity(0.04) : Color.clear)
                    .padding(.horizontal, 1)
            }
            .overlay(alignment: .center) {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(hovering ? WizardDesign.Colors.border.opacity(0.25) : Color.clear, lineWidth: 1)
                    .padding(.horizontal, 1)
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    self.hovering = hovering
                }
            }
            .onTapGesture {
                if isNavigable {
                    onTap?()
                }
            }
    }
}

// MARK: - TCP Probe (synchronous, tiny timeout)

private func probeTCPHelloRequiresStatus(port: Int, timeoutMs: Int) -> Bool {
    var readStream: Unmanaged<CFReadStream>?
    var writeStream: Unmanaged<CFWriteStream>?
    CFStreamCreatePairWithSocketToHost(
        nil, "127.0.0.1" as CFString, UInt32(port), &readStream, &writeStream
    )
    guard let r = readStream?.takeRetainedValue(), let w = writeStream?.takeRetainedValue() else {
        return false
    }
    let input = r as InputStream
    let output = w as OutputStream
    input.open()
    output.open()
    defer {
        input.close()
        output.close()
    }

    // Send Hello request
    let hello = "{\"Hello\":{}}\n"
    if let data = hello.data(using: .utf8) {
        _ = data.withUnsafeBytes {
            output.write($0.bindMemory(to: UInt8.self).baseAddress!, maxLength: data.count)
        }
    }

    let start = Date()
    var buffer = [UInt8](repeating: 0, count: 2048)
    var received = Data()
    var linesChecked = Set<String>() // Track which lines we've already processed

    while Date().timeIntervalSince(start) * 1000.0 < Double(timeoutMs) {
        let n = input.read(&buffer, maxLength: buffer.count)
        if n > 0 {
            received.append(buffer, count: n)
            if let s = String(data: received, encoding: .utf8) {
                // Process all lines, skipping unsolicited broadcasts
                let lines = s.split(separator: "\n").map { String($0) }
                for line in lines where !linesChecked.contains(line) {
                    linesChecked.insert(line)

                    // Skip unsolicited broadcasts (LayerChange, ConfigFileReload, etc.)
                    if line.contains("\"LayerChange\"") || line.contains("\"ConfigFileReload\"")
                        || line.contains("\"MessagePush\"") || line.contains("\"Ready\"")
                        || line.contains("\"ConfigError\"") {
                        continue // Skip this line, read next
                    }

                    // Check for HelloOk with capabilities
                    if line.contains("\"HelloOk\""),
                       let lineData = line.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                       let helloObj = json["HelloOk"] as? [String: Any],
                       let caps = helloObj["capabilities"] as? [String],
                       caps.contains("status") {
                        return true
                    }

                    if line.contains("unknown variant") { return false } // old server
                }
            }
        } else {
            Thread.sleep(forTimeInterval: 0.02)
        }
    }
    return false
}

// MARK: - Status Item Model

struct StatusItemModel {
    let id: String
    let icon: String
    let title: String
    let subtitle: String?
    let status: InstallationStatus
    let isNavigable: Bool
    let targetPage: WizardPage
    let subItems: [StatusItemModel]
    let relatedIssues: [WizardIssue]

    init(
        id: String,
        icon: String,
        title: String,
        subtitle: String? = nil,
        status: InstallationStatus,
        isNavigable: Bool = false,
        targetPage: WizardPage = .summary,
        subItems: [StatusItemModel] = [],
        relatedIssues: [WizardIssue] = []
    ) {
        self.id = id
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.isNavigable = isNavigable
        self.targetPage = targetPage
        self.subItems = subItems
        self.relatedIssues = relatedIssues
    }
}

// MARK: - Focus Ring Suppression

/// NSViewRepresentable that suppresses focus ring drawing on macOS
private struct NoFocusRingBackground: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        view.focusRingType = .none
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        nsView.focusRingType = .none
    }
}

// MARK: - Preview

struct WizardSystemStatusOverview_Previews: PreviewProvider {
    static var previews: some View {
        WizardSystemStatusOverview(
            systemState: .conflictsDetected(conflicts: []),
            issues: [
                WizardIssue(
                    identifier: .conflict(.karabinerGrabberRunning(pid: 123)),
                    severity: .critical,
                    category: .conflicts,
                    title: "Karabiner Conflict",
                    description: "Test conflict",
                    autoFixAction: .terminateConflictingProcesses,
                    userAction: nil
                )
            ],
            stateInterpreter: WizardStateInterpreter(),
            onNavigateToPage: { _ in },
            kanataIsRunning: true, // Show running in preview
            showAllItems: false,
            navSequence: .constant([]),
            visibleIssueCount: .constant(1)
        )
        .padding()
    }
}
