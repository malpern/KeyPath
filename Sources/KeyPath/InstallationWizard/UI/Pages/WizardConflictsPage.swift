import SwiftUI

struct WizardConflictsPage: View {
  let issues: [WizardIssue]
  let isFixing: Bool
  let onAutoFix: () -> Void
  let onRefresh: () async -> Void
  let kanataManager: KanataManager

  @State private var isScanning = false
  @State private var isDisablingPermanently = false

  // Check if there are Karabiner-related conflicts
  private var hasKarabinerConflict: Bool {
    issues.contains { issue in
      issue.description.lowercased().contains("karabiner")
    }
  }

  var body: some View {
    VStack(spacing: WizardDesign.Spacing.sectionGap) {
      // Header using design system
      WizardPageHeader(
        icon: issues.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
        title: issues.isEmpty ? "No Conflicts Detected" : "Conflicting Processes",
        subtitle: issues.isEmpty
          ? "No conflicting keyboard remapping processes found. You're ready to proceed!"
          : "Conflicting keyboard remapping processes must be stopped before continuing",
        status: issues.isEmpty ? .success : .warning
      )

      // Clean Conflicts Card
      if !issues.isEmpty {
        CleanConflictsCard(
          conflictCount: issues.count,
          isFixing: isFixing,
          onAutoFix: onAutoFix,
          issues: issues
        )
        .wizardPagePadding()
      }

      // Information Card
      if issues.isEmpty {
        VStack(spacing: WizardDesign.Spacing.itemGap) {
          HStack(spacing: WizardDesign.Spacing.labelGap) {
            Image(systemName: "checkmark.circle.fill")
              .foregroundColor(WizardDesign.Colors.success)
              .font(WizardDesign.Typography.body)
            Text("System Status: Clean")
              .font(WizardDesign.Typography.status)
          }
          .foregroundColor(WizardDesign.Colors.success)

          Text(
            "KeyPath checked for conflicts and found none. The system is ready for keyboard remapping."
          )
          .font(WizardDesign.Typography.body)
          .foregroundColor(WizardDesign.Colors.secondaryText)
          .multilineTextAlignment(.center)
        }
        .wizardCard()
        .wizardPagePadding()
      }

      Spacer()

      // Action Buttons using design system
      VStack(spacing: WizardDesign.Spacing.elementGap) {
        if !issues.isEmpty && issues.first?.autoFixAction != nil {
          Button("Terminate Conflicting Processes") {
            onAutoFix()
          }
          .buttonStyle(WizardDesign.Component.PrimaryButton(isLoading: isFixing))
          .disabled(isFixing)

          // Add permanent disable option for Karabiner Elements
          if hasKarabinerConflict {
            Button(action: {
              Task {
                isDisablingPermanently = true
                let success = await kanataManager.disableKarabinerElementsPermanently()
                if success {
                  await onRefresh()
                }
                isDisablingPermanently = false
              }
            }) {
              Text(
                isDisablingPermanently ? "Disabling..." : "Permanently Disable Conflicting Services"
              )
            }
            .buttonStyle(
              WizardDesign.Component.DestructiveButton(isLoading: isDisablingPermanently)
            )
            .disabled(isDisablingPermanently || isFixing)
          }
        }

        Button(action: {
          Task {
            isScanning = true
            await onRefresh()
            // Keep spinner visible for a moment so user sees the action
            try? await Task.sleep(nanoseconds: 500_000_000)
            isScanning = false
          }
        }) {
          Text(
            isScanning ? "Scanning..." : (issues.isEmpty ? "Re-scan for Conflicts" : "Check Again"))
        }
        .buttonStyle(WizardDesign.Component.SecondaryButton(isLoading: isScanning))
        .disabled(isFixing || isScanning)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(WizardDesign.Colors.wizardBackground)
  }
}

// MARK: - Clean Conflicts Card (Following macOS HIG)

struct CleanConflictsCard: View {
  let conflictCount: Int
  let isFixing: Bool
  let onAutoFix: () -> Void
  let issues: [WizardIssue]

  @State private var showingDetails = false

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

        // Primary Action - Large, Prominent
        Button(action: onAutoFix) {
          HStack(spacing: 8) {
            if isFixing {
              ProgressView()
                .scaleEffect(0.8)
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
            }
            Text(isFixing ? "Stopping Processes..." : "Stop Conflicting Processes")
              .font(.headline)
              .fontWeight(.medium)
          }
          .frame(minWidth: 240, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isFixing)

        // Progressive Disclosure - Show Details Option
        DisclosureGroup("Show technical details", isExpanded: $showingDetails) {
          TechnicalDetailsView(issues: issues)
            .padding(.top, WizardDesign.Spacing.itemGap)
        }
        .font(.subheadline)
        .foregroundColor(.secondary)
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

  private var processDetails: [String] {
    var details: [String] = []

    for issue in issues {
      if issue.category == .conflicts {
        let lines = issue.description.components(separatedBy: "\n")
        for line in lines {
          if line.contains("Process ID:") {
            let cleanLine = line.replacingOccurrences(of: "• ", with: "")
            details.append(cleanLine)
          }
        }
      }
    }

    return details
  }

  var body: some View {
    VStack(alignment: .leading, spacing: WizardDesign.Spacing.labelGap) {
      ForEach(Array(processDetails.enumerated()), id: \.offset) { _, detail in
        Text(detail)
          .font(.caption)
          .foregroundColor(.secondary)
          .padding(.vertical, 4)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(WizardDesign.Spacing.itemGap)
    .background(Color(.separatorColor).opacity(0.3))
    .cornerRadius(8)
  }
}
