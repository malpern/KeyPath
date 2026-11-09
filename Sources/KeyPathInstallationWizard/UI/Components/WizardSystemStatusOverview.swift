import AppKit
import KeyPathCore
import KeyPathPermissions
import KeyPathWizardCore
import SwiftUI

/// Simplified system status overview component for the summary page
public struct WizardSystemStatusOverview: View {
    public let systemState: WizardSystemState
    public let issues: [WizardIssue]
    /// Permission facts captured with the same wizard snapshot, when available.
    public let permissions: PermissionOracle.Snapshot?
    public let onNavigateToPage: ((WizardPage) -> Void)?
    /// Authoritative signal for service status - ensures consistency with detail page
    public let kanataIsRunning: Bool
    /// When false, show only items that need attention (failed). When true, show all.
    public let showAllItems: Bool
    /// Ordered navigation sequence, synced to current display filter
    @Binding public var navSequence: [WizardPage]
    /// Number of visible items that are not completed (used by summary header)
    @Binding public var visibleIssueCount: Int

    public init(
        systemState: WizardSystemState,
        issues: [WizardIssue],
        permissions: PermissionOracle.Snapshot? = nil,
        onNavigateToPage: ((WizardPage) -> Void)?,
        kanataIsRunning: Bool,
        showAllItems: Bool,
        navSequence: Binding<[WizardPage]>,
        visibleIssueCount: Binding<Int>
    ) {
        self.systemState = systemState
        self.issues = issues
        self.permissions = permissions
        self.onNavigateToPage = onNavigateToPage
        self.kanataIsRunning = kanataIsRunning
        self.showAllItems = showAllItems
        _navSequence = navSequence
        _visibleIssueCount = visibleIssueCount
    }

    public var body: some View {
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
            // Center to 50% of window width (window width is fixed by layout)
            .frame(width: WizardDesign.Layout.pageWidth * 0.5)
            .padding(.vertical, WizardDesign.Spacing.sectionGap)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollIndicators(.hidden)
        .focusable(false)
        .modifier(WizardDesign.DisableFocusEffects())
        .background(Color.clear)
        .onAppear {
            // Aggressively disable focus ring on underlying NSView (deferred for AppKit interop)
            Task { @MainActor in
                if let window = NSApp.keyWindow,
                   let contentView = window.contentView
                {
                    disableFocusRings(in: contentView)
                }
            }
        }
        .onAppear {
            updateNavSequence()
        }
        .onChange(of: showAllItems) { _, _ in updateNavSequence() }
        .onChange(of: issues.count) { _, _ in updateNavSequence() }
        .onChange(of: systemState) { _, _ in updateNavSequence() }
        .onChange(of: statusFingerprint) { _, _ in updateNavSequence() }
        // Scroll fade overlays removed — they created visible grey stripe artifacts
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

    /// Items to render given the current toggle state
    private var displayItems: [StatusItemModel] {
        Self.filteredDisplayItems(statusItems, showAllItems: showAllItems)
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

    /// Internal for tests: accessed via @testable without adding a dedicated test-only accessor.
    public var statusItems: [StatusItemModel] {
        Self.sessionStatusItems(systemState: systemState, issues: issues, permissions: permissions)
    }

    private var statusFingerprint: String {
        statusItems.map { "\($0.id):\($0.status)" }.joined(separator: "|")
    }

    /// The session runtime requires only KeyPath's Accessibility grant and the
    /// runtime itself.
    static func sessionStatusItems(
        systemState: WizardSystemState,
        issues: [WizardIssue],
        permissions: PermissionOracle.Snapshot? = nil
    ) -> [StatusItemModel] {
        let accessibilityIssues = issues.filter(\.identifier.isPermission)
        let runtimeIssues = issues.filter { issue in
            if issue.identifier == .daemon { return true }
            if case .component(.bundledKanataMissing) = issue.identifier { return true }
            return false
        }

        func status(for matchingIssues: [WizardIssue], permissionReady: Bool?) -> InstallationStatus {
            guard !matchingIssues.isEmpty else {
                if systemState == .active || permissionReady == true { return .completed }
                return .notStarted
            }
            let mapped = IssueSeverityInstallationStatusMapper.installationStatus(for: matchingIssues)
            // Unknown permission/runtime evidence stays unresolved and visible;
            // it must not be presented as a confirmed grant.
            return mapped == .unverified ? .notStarted : mapped
        }

        return [
            StatusItemModel(
                id: "accessibility",
                icon: "accessibility",
                title: AccessibilityPermissionPresentation.current.name,
                status: status(
                    for: accessibilityIssues,
                    permissionReady: permissions?.isSystemReady
                ),
                isNavigable: true,
                targetPage: .accessibility,
                relatedIssues: accessibilityIssues
            ),
            StatusItemModel(
                id: "kanata-service",
                icon: "app.badge.checkmark",
                title: "KeyPath Runtime",
                subtitle: systemState == .active ? "Running" : nil,
                status: status(for: runtimeIssues, permissionReady: nil),
                isNavigable: true,
                targetPage: .service,
                relatedIssues: runtimeIssues
            )
        ]
    }

    static func incompleteItemCount(_ items: [StatusItemModel]) -> Int {
        items.filter { $0.status != .completed && $0.status != .unverified }.count
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
        // Don't count unverified items as issues - we can't verify them anyway
        visibleIssueCount = Self.incompleteItemCount(displayItems)
        AppLogger.shared.log(
            "🔍 [NavSeq] ✅ navSequence updated: \(ordered.count) pages: \(ordered.map(\.displayName))"
        )
    }

    // MARK: - Filtering helper (shared with tests)

    public static func filteredDisplayItems(_ items: [StatusItemModel], showAllItems: Bool)
        -> [StatusItemModel]
    {
        if showAllItems {
            return items
        }
        // Show incomplete items. Treat .unverified as "complete enough" - we can't verify it,
        // so don't alarm the user with it in the issues list.
        return items.filter { $0.status != .completed && $0.status != .unverified }
    }

    // MARK: - Status Item Model

    public struct StatusItemModel {
        public let id: String
        public let icon: String
        public let title: String
        public let subtitle: String?
        public let status: InstallationStatus
        public let isNavigable: Bool
        public let targetPage: WizardPage
        public let subItems: [StatusItemModel]
        public let relatedIssues: [WizardIssue]

        public init(
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

    /// Public alias for tests and other modules.
    typealias WizardStatusItemModel = StatusItemModel

    // MARK: - Status Helpers

    public func getServiceStatus() -> InstallationStatus {
        if systemState == .initializing {
            return .inProgress
        }

        let daemonIssues = issues.filter(\.identifier.isDaemon)
        if !daemonIssues.isEmpty {
            return issueStatus(for: daemonIssues)
        }

        if ServiceStatusEvaluator.blockingIssueMessage(from: issues) != nil {
            return .failed
        }

        if kanataIsRunning {
            return .completed
        }

        return .notStarted
    }

    private func issueStatus(for issues: [WizardIssue]) -> InstallationStatus {
        IssueSeverityInstallationStatusMapper.installationStatus(for: issues)
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
