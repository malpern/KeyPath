import AppKit
import KeyPathCore
import KeyPathWizardCore
import SwiftUI

/// Preference key that tracks the content height of the wizard page,
/// enabling auto-resize on any content change (not just page transitions).
public struct WizardContentHeightKey: PreferenceKey {
    public static let defaultValue: CGFloat = 0
    public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Main installation wizard view using clean architecture
public struct InstallationWizardView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.runtimeCoordinator) var kanataManager

    @MainActor
    public func showStatusBanner(_ message: String) {
        statusBannerMessage = message
        statusBannerTimestamp = Date()

        // Auto-dismiss after 6 seconds if not updated
        let marker = statusBannerTimestamp
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
            // Ensure we only clear if timestamp matches (no newer message arrived)
            if marker == statusBannerTimestamp {
                statusBannerMessage = nil
            }
        }
    }

    /// Optional initial page to navigate to
    public var initialPage: WizardPage?

    // New architecture components
    @State public var stateMachine = WizardStateMachine()
    @State public var asyncOperationManager = WizardAsyncOperationManager()
    public var isOperationRunning: Bool { asyncOperationManager.hasRunningOperations }
    @State public var toastManager = WizardToastManager()

    // UI state
    @State public var isValidating: Bool = true // Track validation state for summary activity indicator
    @State public var preflightStart = Date()
    @State public var evaluationProgress: Double = 0.0
    // stateMachine.wizardState and stateMachine.wizardIssues now live in stateMachine (single source of truth)
    @State public var showAllSummaryItems: Bool = false
    @State public var navSequence: [WizardPage] = []
    @State public var inFlightFixActions: Set<AutoFixAction> = []
    @State public var showingBackgroundApprovalPrompt = false
    @State public var currentFixAction: AutoFixAction?
    @State public var fixInFlight: Bool = false
    @State public var lastRefreshAt: Date?
    @State public var showingCloseConfirmation = false

    // Task management for race condition prevention
    @State public var refreshTask: Task<Void, Never>?
    @State public var isForceClosing = false // Prevent new operations after nuclear close
    @State public var loginItemsPollingTask: Task<Void, Never>? // Polls for Login Items approval
    @State public var statusBannerMessage: String?
    @State public var statusBannerTimestamp: Date?

    /// Focus management for reliable ESC key handling
    @FocusState private var hasKeyboardFocus: Bool

    /// True when the current page is already showing a contextual/in-page progress indicator.
    /// Used to suppress the global operation overlay to avoid duplicate progress treatments.
    @State private var hasInlineProgressIndicator: Bool = false

    public init(initialPage: WizardPage? = nil) {
        self.initialPage = initialPage
    }

    public var currentFixDescriptionForUI: String? {
        guard let currentFixAction else { return nil }
        return describeAutoFixActionForUI(currentFixAction)
    }

    public var body: some View {
        ZStack {
            statusBanner
            WizardDesign.Colors.wizardBackground
                .ignoresSafeArea()
            pageContainer
        }
        .withToasts(toastManager)
        .environment(stateMachine)
        .focused($hasKeyboardFocus)
        .onChange(of: isValidating, handleValidationChange)
        .overlay(alignment: .top) { navigationOverlay }
        .onAppear {
            hasKeyboardFocus = true
            Task { await setupWizard() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowUserFeedback"))) { note in
            if let message = note.userInfo?["message"] as? String {
                showStatusBanner(message)
            }
        }
        .onChange(of: isOperationRunning) { _, newValue in
            if !newValue { hasKeyboardFocus = true }
        }
        .onChange(of: showAllSummaryItems) { _, showAll in
            stateMachine.customSequence = showAll ? nil : navSequence
        }
        .onChange(of: stateMachine.currentPage) { oldPage, newPage in
            handlePageChange(from: oldPage, to: newPage)
        }
        .onChange(of: navSequence) { _, newSeq in
            if !showAllSummaryItems { stateMachine.customSequence = newSeq }
        }
        .onChange(of: showingCloseConfirmation) { _, newValue in
            if !newValue { hasKeyboardFocus = true }
        }
        .modifier(
            KeyboardNavigationModifier(
                onLeftArrow: navigateToPreviousPage,
                onRightArrow: navigateToNextPage,
                onEscape: forciblyCloseWizard
            )
        )
        .onExitCommand { forciblyCloseWizard() }
        .task { await monitorSystemState() }
        .onReceive(NotificationCenter.default.publisher(for: .wizardSmAppServiceApprovalRequired)) { _ in
            showingBackgroundApprovalPrompt = true
        }
        .alert("Close Setup Wizard?", isPresented: $showingCloseConfirmation) {
            closeConfirmationButtons
        } message: {
            closeConfirmationMessage
        }
        .alert("Enable KeyPath in Login Items", isPresented: $showingBackgroundApprovalPrompt) {
            loginItemsApprovalButtons
        } message: {
            Text("Login Items will open. Find KeyPath under Background Items and flip the switch to enable it.")
        }
        .onChange(of: showingBackgroundApprovalPrompt) { _, isShowing in
            if isShowing { startLoginItemsApprovalPolling() }
        }
    }

    // MARK: - Body Sections

    @ViewBuilder
    private var statusBanner: some View {
        if let banner = statusBannerMessage {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                    Text(banner)
                        .font(.callout)
                        .multilineTextAlignment(.leading)
                    Spacer()
                }
                .padding(10)
                .background(.thinMaterial)
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Color.gray.opacity(0.15)),
                    alignment: .bottom
                )
                Spacer()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .zIndex(2)
        }
    }

    private var pageContainer: some View {
        VStack(spacing: 0) {
            pageContent()
                .id(stateMachine.currentPage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(GeometryReader { geo in
                    Color.clear.preference(key: WizardContentHeightKey.self, value: geo.size.height)
                })
                .onPreferenceChange(WizardContentHeightKey.self) { _ in
                    NotificationCenter.default.post(name: .wizardContentSizeChanged, object: nil)
                }
                .onPreferenceChange(WizardInlineProgressVisiblePreferenceKey.self) { newValue in
                    hasInlineProgressIndicator = newValue
                }
                .overlay {
                    if isOperationRunning, !isValidating, !hasInlineProgressIndicator {
                        operationProgressOverlay()
                            .allowsHitTesting(false)
                    }
                }
        }
        .frame(width: WizardDesign.Layout.pageWidth)
        .frame(minHeight: 480, maxHeight: .infinity)
        .fixedSize(horizontal: true, vertical: false)
        .animation(.easeInOut(duration: 0.25), value: isValidating)
        .animation(nil, value: stateMachine.currentPage)
        .background(WizardDesign.Colors.wizardBackground)
    }

    @ViewBuilder
    private var navigationOverlay: some View {
        if stateMachine.currentPage != .summary {
            HStack {
                WizardNavigationControl()
                Spacer()
                CloseButton()
            }
            .environment(stateMachine)
            .padding(.top, 12)
            .padding(.horizontal, 12)
            .animation(nil, value: stateMachine.currentPage)
        }
    }

    // MARK: - Alert Content

    @ViewBuilder
    private var closeConfirmationButtons: some View {
        Button("Cancel", role: .cancel) {
            showingCloseConfirmation = false
        }
        Button("Close Anyway", role: .destructive) {
            forceInstantClose()
            performBackgroundCleanup()
        }
        .keyboardShortcut(.defaultAction)
    }

    private var closeConfirmationMessage: some View {
        let criticalCount = stateMachine.wizardIssues.filter { $0.severity == .critical }.count
        return Text(
            "There \(criticalCount == 1 ? "is" : "are") \(criticalCount) critical \(criticalCount == 1 ? "issue" : "issues") "
                + "that may prevent KeyPath from working properly. Are you sure you want to close the setup wizard?"
        )
    }

    @ViewBuilder
    private var loginItemsApprovalButtons: some View {
        Button("OK") {
            showingBackgroundApprovalPrompt = false
            openLoginItemsSettings()
        }
        .keyboardShortcut(.defaultAction)
        Button("Later", role: .cancel) {
            showingBackgroundApprovalPrompt = false
            stopLoginItemsApprovalPolling()
        }
    }

    // MARK: - Event Handlers

    private func handleValidationChange(_: Bool, _ newValue: Bool) {
        if newValue {
            Task { @MainActor in
                NSApp.keyWindow?.makeFirstResponder(nil)
                if let window = NSApp.keyWindow, let contentView = window.contentView {
                    disableFocusRings(in: contentView)
                }
            }
        } else {
            stateMachine.customSequence = showAllSummaryItems ? nil : navSequence
        }
    }
}
