import SwiftUI

struct WizardConflictsPage: View {
    let issues: [WizardIssue]
    let isFixing: Bool
    let onAutoFix: () -> Void
    let onRefresh: () -> Void
    let kanataManager: KanataManager

    @State private var isScanning = false
    @EnvironmentObject var navigationCoordinator: WizardNavigationCoordinator
    @State private var isDisablingPermanently = false

    // Check if there are Karabiner-related conflicts
    private var hasKarabinerConflict: Bool {
        issues.contains { issue in
            issue.description.lowercased().contains("karabiner")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if issues.isEmpty {
                // Large centered hero section - Icon, Headline, and Supporting Copy
                VStack(spacing: 0) {
                    Spacer()

                    // Centered hero block with padding
                    VStack(spacing: WizardDesign.Spacing.sectionGap) {
                        // Large green check for success
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 115, weight: .light))
                            .foregroundColor(WizardDesign.Colors.success)
                            .symbolRenderingMode(.hierarchical)
                            .symbolEffect(.bounce, options: .nonRepeating)

                        // Larger headline (23pt to match Full Disk Access)
                        Text("No Conflicts Detected")
                            .font(.system(size: 23, weight: .semibold, design: .default))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)

                        // Supporting copy - shortened
                        Text("No conflicting keyboard remapping software found")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        // Blue links under the subheading
                        HStack(spacing: WizardDesign.Spacing.itemGap) {
                            Button(action: {
                                isScanning = true
                                onRefresh()
                                // Keep spinner visible for a moment so user sees the action
                                Task {
                                    try? await Task.sleep(nanoseconds: 500_000_000)
                                    isScanning = false
                                }
                            }) {
                                HStack(spacing: 4) {
                                    if isScanning {
                                        ProgressView()
                                            .scaleEffect(0.6)
                                            .progressViewStyle(CircularProgressViewStyle())
                                    }
                                    Text(isScanning ? "Scanning..." : "Check Again")
                                }
                            }
                            .buttonStyle(.link)
                            .disabled(isFixing || isScanning)

                            Text("•")
                                .foregroundColor(.secondary)

                            Button("Reset Everything") {
                                Task {
                                    isScanning = true
                                    let toastManager = WizardToastManager() // Temporary instance for reset operation
                                    let autoFixer = WizardAutoFixer(kanataManager: kanataManager, toastManager: toastManager)
                                    await autoFixer.resetEverything()
                                    onRefresh()
                                    isScanning = false
                                }
                            }
                            .buttonStyle(.link)
                            .foregroundColor(.red)
                            .disabled(isFixing || isScanning)
                            .help("Kill all processes, clear PID files, and reset to clean state")
                        }
                        .padding(.top, WizardDesign.Spacing.elementGap)
                    }
                    .padding(.vertical, WizardDesign.Spacing.pageVertical) // Add padding above and below the hero block

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // No component details - conflicts are system-wide, no individual components to fix
            } else {
                // Original design for when conflicts are detected
                VStack(spacing: WizardDesign.Spacing.sectionGap) {
                    // Custom header with colored triangle icon
                    VStack(spacing: WizardDesign.Spacing.elementGap) {
                        // Simple warning icon for errors
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 60, weight: .light))
                            .foregroundColor(WizardDesign.Colors.error)
                            .symbolRenderingMode(.hierarchical)
                            .symbolEffect(.bounce, options: .nonRepeating)
                            .frame(width: WizardDesign.Layout.statusCircleSize, height: WizardDesign.Layout.statusCircleSize)
                        
                        // Title
                        Text("Conflicts Detected")
                            .font(WizardDesign.Typography.sectionTitle)
                            .fontWeight(.semibold)
                        
                        // Subtitle
                        Text("\(issues.count) conflicting process\(issues.count == 1 ? "" : "es") found that must be resolved.")
                            .font(WizardDesign.Typography.subtitle)
                            .foregroundColor(WizardDesign.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                            .wizardContentSpacing()
                    }
                    .padding(.top, 12)

                    // Main content area with conflicts
                    VStack(alignment: .leading, spacing: WizardDesign.Spacing.itemGap) {
                        // Show conflicts with auto-fix options
                        CleanConflictsCard(
                            conflictCount: issues.count,
                            isFixing: isFixing,
                            onAutoFix: onAutoFix,
                            onRefresh: onRefresh,
                            issues: issues,
                            kanataManager: kanataManager
                        )

                        Spacer(minLength: 60)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(WizardDesign.Spacing.cardPadding)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, WizardDesign.Spacing.pageVertical)
                }
            }

            // Smaller spacing before buttons
            Spacer()
                .frame(height: WizardDesign.Spacing.sectionGap)

            // Primary Continue button for no-conflict state, existing buttons for conflict state
            VStack {
                if issues.isEmpty {
                    // No conflicts - show only Continue button centered
                    Button("Continue") {
                        AppLogger.shared.log("ℹ️ [Wizard] User continuing from Conflicts page")
                        navigateToNextPage()
                    }
                    .buttonStyle(WizardDesign.Component.PrimaryButton())
                } else {
                    // Conflicts detected - show existing button pattern
                    HStack(spacing: WizardDesign.Spacing.itemGap) {
                        // Existing buttons on the left/center
                        Button(action: {
                            isScanning = true
                            onRefresh()
                            // Keep spinner visible for a moment so user sees the action
                            Task {
                                try? await Task.sleep(nanoseconds: 500_000_000)
                                isScanning = false
                            }
                        }) {
                            HStack(spacing: 4) {
                                if isScanning {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .progressViewStyle(CircularProgressViewStyle())
                                }
                                Text(
                                    isScanning
                                        ? "Scanning..." : "Check Again"
                                )
                            }
                        }
                        .buttonStyle(WizardDesign.Component.SecondaryButton())
                        .disabled(isFixing || isScanning)

                        // Reset button for nuclear option
                        Button("Reset Everything") {
                            Task {
                                isScanning = true
                                let toastManager = WizardToastManager() // Temporary instance for reset operation
                                let autoFixer = WizardAutoFixer(kanataManager: kanataManager, toastManager: toastManager)
                                await autoFixer.resetEverything()
                                onRefresh()
                                isScanning = false
                            }
                        }
                        .buttonStyle(WizardDesign.Component.SecondaryButton())
                        .foregroundColor(.red)
                        .disabled(isFixing || isScanning)
                        .help("Kill all processes, clear PID files, and reset to clean state")

                        Spacer()

                        // Primary continue button (always present, far right)
                        Button("Continue") {
                            AppLogger.shared.log("ℹ️ [Wizard] User continuing from Conflicts page")
                            navigateToNextPage()
                        }
                        .buttonStyle(WizardDesign.Component.PrimaryButton())
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, WizardDesign.Spacing.sectionGap)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WizardDesign.Colors.wizardBackground)
        .onAppear {
            // Force a refresh when the page appears to avoid stale conflict snapshots
            onRefresh()
        }
    }

    // MARK: - Helper Methods

    private func navigateToNextPage() {
        let allPages = WizardPage.allCases
        guard let currentIndex = allPages.firstIndex(of: navigationCoordinator.currentPage),
              currentIndex < allPages.count - 1
        else { return }
        let nextPage = allPages[currentIndex + 1]
        navigationCoordinator.navigateToPage(nextPage)
        AppLogger.shared.log("➡️ [Conflicts] Navigated to next page: \(nextPage.displayName)")
    }
}

// MARK: - Clean Conflicts Card (Following macOS HIG)

struct CleanConflictsCard: View {
    let conflictCount: Int
    let isFixing: Bool
    let onAutoFix: () -> Void
    let onRefresh: () -> Void
    let issues: [WizardIssue]
    let kanataManager: KanataManager

    @State private var showingDetails = false
    @State private var isPerformingPermanentFix = false
    @State private var showSuccessMessage = false
    @State private var showErrorMessage = false
    @State private var statusMessage = ""

    var body: some View {
        VStack(spacing: WizardDesign.Spacing.sectionGap) {
            // Main Card - Simple and Clear
            VStack(alignment: .center, spacing: WizardDesign.Spacing.sectionGap) {
                // Large Warning Icon
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(WizardDesign.Colors.warning)

                // Primary Message - Large, Readable
                VStack(spacing: WizardDesign.Spacing.labelGap) {
                    Text("Conflicting Processes Found")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)

                    Text(
                        "\(conflictCount) process\(conflictCount == 1 ? "" : "es") must be stopped before continuing"
                    )
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                }

                // Primary Action - Resolve Conflicts Permanently
                Button(action: {
                    Task {
                        isPerformingPermanentFix = true

                        // Try permanent fix first (what most users want)
                        let success = await kanataManager.disableKarabinerElementsPermanently()

                        if !success {
                            // Show error message explaining what happened
                            statusMessage = "Permanent fix cancelled or failed. Try the temporary fix below."
                            showErrorMessage = true

                            // Hide error message after a few seconds
                            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                                showErrorMessage = false
                            }
                        } else {
                            // Show success message
                            statusMessage =
                                "Conflicts permanently resolved! Karabiner Elements has been disabled."
                            showSuccessMessage = true

                            // Give user feedback that permanent fix succeeded
                            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds

                            // Trigger a refresh to update the conflict state
                            onRefresh()

                            // Hide success message
                            showSuccessMessage = false
                        }

                        isPerformingPermanentFix = false
                    }
                }) {
                    HStack(spacing: 8) {
                        if isFixing || isPerformingPermanentFix {
                            ProgressView()
                                .scaleEffect(0.8)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                        Text(
                            isFixing || isPerformingPermanentFix
                                ? "Resolving Conflict\(conflictCount == 1 ? "" : "s")..."
                                : "Resolve Conflict\(conflictCount == 1 ? "" : "s")"
                        )
                        .font(.headline)
                        .fontWeight(.medium)
                    }
                    .frame(minWidth: 240, minHeight: 44)
                }
                .buttonStyle(WizardDesign.Component.PrimaryButton())
                .disabled(isFixing || isPerformingPermanentFix)

                // Secondary Option - Temporary Fix
                Button(action: onAutoFix) {
                    Text("Temporary Fix Only")
                        .font(.subheadline)
                }
                .buttonStyle(WizardDesign.Component.SecondaryButton())
                .disabled(isFixing || isPerformingPermanentFix)

                // Status Messages
                if showSuccessMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(statusMessage)
                            .font(.subheadline)
                            .foregroundColor(.green)
                    }
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if showErrorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(statusMessage)
                            .font(.subheadline)
                            .foregroundColor(.orange)
                    }
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Progressive Disclosure - Show Details Option
                VStack(spacing: WizardDesign.Spacing.itemGap) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingDetails.toggle()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: showingDetails ? "chevron.down" : "chevron.right")
                                .font(.caption)
                            Text(showingDetails ? "Hide technical details" : "Show technical details")
                                .font(.subheadline)
                        }
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.link)

                    if showingDetails {
                        TechnicalDetailsView(issues: issues, kanataManager: kanataManager)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }
            }
            .padding(WizardDesign.Spacing.pageVertical)
            .frame(maxWidth: 500)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
        }
    }
}

// MARK: - Technical Details View (Hidden by Default)

struct TechnicalDetailsView: View {
    let issues: [WizardIssue]
    let kanataManager: KanataManager
    @State private var conflictDetectionResult: ConflictDetectionResult?
    @State private var isLoadingConflicts = false

    private var processDetails: [String] {
        var details: [String] = []

        for issue in issues {
            if issue.category == .conflicts {
                // Add the main description
                details.append("Issue: \(issue.title)")

                // Split description into lines and process each
                let lines = issue.description.components(separatedBy: "\n")
                for line in lines {
                    let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedLine.isEmpty {
                        // Clean up bullet points and add all non-empty lines
                        let cleanLine = trimmedLine.replacingOccurrences(of: "• ", with: "")
                        if !cleanLine.isEmpty {
                            details.append("• \(cleanLine)")
                        }
                    }
                }
            }
        }

        // If no details found, show debugging info
        if details.isEmpty {
            details.append("Debug: Found \(issues.count) issues")
            for (index, issue) in issues.enumerated() {
                details.append("Issue \(index + 1): \(issue.title)")
                details.append("Description preview: \(String(issue.description.prefix(100)))")
            }
        }

        return details
    }

    // Helper function to parse process information
    private func parseProcessInfo(_ text: String) -> (name: String, description: String, pid: String) {
        // Extract PID using regex - handle both formats: "PID: 123" and "(PID: 123)"
        let pidPattern = #"PID: (\d+)"#
        var pid = "unknown"
        if let pidMatch = text.range(of: pidPattern, options: .regularExpression) {
            let pidText = String(text[pidMatch])
            // Extract just the number part
            if let numberMatch = pidText.range(of: #"\d+"#, options: .regularExpression) {
                pid = String(pidText[numberMatch])
            }
        }

        // Match different types of conflicts
        if text.contains("Karabiner Elements grabber") || text.contains("karabiner_grabber") {
            return ("karabiner_grabber", "Keyboard input capture daemon", pid)
        } else if text.contains("VirtualHIDDevice") || text.contains("Karabiner-VirtualHIDDevice") {
            return ("VirtualHIDDevice", "Virtual keyboard/mouse driver", pid)
        } else if text.contains("Kanata process") || text.contains("kanata") {
            return ("kanata", "Keyboard remapping engine", pid)
        }

        // If we have a valid PID but unknown process type, it's still better than complete unknown
        if pid != "unknown", pid != "-1" {
            return ("system_process", "System process", pid)
        }

        // Default fallback
        return ("unknown_process", "System process", "unknown")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header section
            Text("Process Details")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            if isLoadingConflicts {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Detecting processes...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                // Show managed processes with green checks
                if let result = conflictDetectionResult, !result.managedProcesses.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("KeyPath Managed Processes")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.green)

                        ForEach(result.managedProcesses.indices, id: \.self) { index in
                            let process = result.managedProcesses[index]
                            ProcessRow(
                                processName: "kanata",
                                processDescription: "Keyboard remapping engine (managed)",
                                pid: String(process.pid),
                                statusColor: .green,
                                statusIcon: "checkmark.circle.fill"
                            )
                        }
                    }
                }

                // Show external conflicts with red X
                if !processDetails.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        if conflictDetectionResult?.managedProcesses.isEmpty == false {
                            Divider()
                                .padding(.vertical, 4)
                        }

                        Text("External Conflicts")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.red)

                        ForEach(Array(processDetails.enumerated()), id: \.offset) { _, detail in
                            if detail.hasPrefix("•") {
                                let processText = detail.replacingOccurrences(of: "• ", with: "")

                                // Only display lines that actually contain PID information
                                if processText.contains("PID: "),
                                   processText.range(of: #"PID: \d+"#, options: .regularExpression) != nil {
                                    let (processName, processDescription, pid) = parseProcessInfo(processText)
                                    ProcessRow(
                                        processName: processName,
                                        processDescription: processDescription,
                                        pid: pid,
                                        statusColor: .red,
                                        statusIcon: "xmark.circle.fill"
                                    )
                                }
                            }
                        }
                    }
                }

                // If no processes found
                if conflictDetectionResult?.managedProcesses.isEmpty != false, processDetails.isEmpty {
                    Text("No processes detected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color(.quaternaryLabelColor), lineWidth: 0.5)
                )
        )
        .shadow(color: .black.opacity(0.02), radius: 4, x: 0, y: 1)
        .task {
            await loadConflictDetails()
        }
    }

    private func loadConflictDetails() async {
        isLoadingConflicts = true
        let processLifecycleManager = ProcessLifecycleManager(kanataManager: kanataManager)
        let conflicts = await processLifecycleManager.detectConflicts()

        await MainActor.run {
            conflictDetectionResult = ConflictDetectionResult(
                conflicts: [],
                canAutoResolve: conflicts.canAutoResolve,
                description: "",
                managedProcesses: conflicts.managedProcesses
            )
            isLoadingConflicts = false
        }
    }
}

// MARK: - Process Row Component

struct ProcessRow: View {
    let processName: String
    let processDescription: String
    let pid: String
    let statusColor: Color
    let statusIcon: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Status indicator
            Image(systemName: statusIcon)
                .foregroundColor(statusColor)
                .font(.system(size: 16, weight: .medium))

            VStack(alignment: .leading, spacing: 2) {
                Text(processName)
                    .font(.custom("Courier New", size: 14))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(processDescription) (PID: \(pid))")
                    .font(.custom("Courier New", size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }
}
