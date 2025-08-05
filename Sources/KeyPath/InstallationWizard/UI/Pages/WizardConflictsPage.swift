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
      // Header using design system - simplified for no conflicts case
      if issues.isEmpty {
        WizardPageHeader(
          icon: "checkmark.circle.fill",
          title: "No Conflicts Detected",
          subtitle: "No conflicting keyboard remapping processes found. You're ready to proceed!",
          status: .success
        )
      }

      // Clean Conflicts Card - handles conflicts case with its own header
      if !issues.isEmpty {
        CleanConflictsCard(
          conflictCount: issues.count,
          isFixing: isFixing,
          onAutoFix: onAutoFix,
          issues: issues,
          kanataManager: kanataManager
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

      // Simple link for re-scanning with proper padding
      HStack {
        Spacer()
        Button(action: {
          Task {
            isScanning = true
            await onRefresh()
            // Keep spinner visible for a moment so user sees the action
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
                ? "Scanning..." : (issues.isEmpty ? "Re-scan for Conflicts" : "Check Again")
            )
            .font(.subheadline)
          }
          .foregroundColor(.blue)
        }
        .buttonStyle(.plain)
        .disabled(isFixing || isScanning)
        Spacer()
      }
      .padding(.bottom, 32)  // Add comfortable padding from bottom
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
  let kanataManager: KanataManager

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

        // Primary Action - Resolve Conflicts Permanently
        Button(action: {
          Task {
            // Try permanent fix first (what most users want)
            let success = await kanataManager.disableKarabinerElementsPermanently()
            if !success {
              // Fallback to temporary fix if permanent fails
              onAutoFix()
            }
          }
        }) {
          HStack(spacing: 8) {
            if isFixing {
              ProgressView()
                .scaleEffect(0.8)
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
            }
            Text(
              isFixing
                ? "Resolving Conflict\(conflictCount == 1 ? "" : "s")..."
                : "Resolve Conflict\(conflictCount == 1 ? "" : "s")"
            )
            .font(.headline)
            .fontWeight(.medium)
          }
          .frame(minWidth: 240, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isFixing)

        // Secondary Option - Temporary Fix
        Button(action: onAutoFix) {
          Text("Temporary Fix Only")
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .disabled(isFixing)

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
          .buttonStyle(.plain)

          if showingDetails {
            TechnicalDetailsView(issues: issues)
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

        // Add identifier info if available
        details.append("Category: \(issue.category)")
        details.append("Severity: \(issue.severity)")
      }
    }

    // If no details found, show debugging info
    if details.isEmpty {
      details.append("Debug: Found \(issues.count) issues")
      for (index, issue) in issues.enumerated() {
        details.append("Issue \(index + 1): \(issue.title)")
        details.append("Category: \(issue.category)")
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
    if pid != "unknown" && pid != "-1" {
      return ("system_process", "System process", pid)
    }

    // Default fallback
    return ("unknown_process", "System process", "unknown")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Header section with cleaner typography
      VStack(alignment: .leading, spacing: 16) {
        Text("Conflicting Processes Detected")
          .font(.headline)
          .fontWeight(.semibold)
          .foregroundColor(.primary)

        // Process list with monospace font - only show lines with actual PIDs
        VStack(alignment: .leading, spacing: 12) {
          ForEach(Array(processDetails.enumerated()), id: \.offset) { _, detail in
            if detail.hasPrefix("•") {
              let processText = detail.replacingOccurrences(of: "• ", with: "")

              // Only display lines that actually contain PID information
              if processText.contains("PID: ")
                && processText.range(of: #"PID: \d+"#, options: .regularExpression) != nil {
                VStack(alignment: .leading, spacing: 4) {
                  HStack(alignment: .center, spacing: 12) {
                    // Modern status indicator
                    Circle()
                      .fill(Color.orange)
                      .frame(width: 6, height: 6)

                    // Extract process name, description, and PID
                    let (processName, processDescription, pid) = parseProcessInfo(processText)

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
                }
              }
            }
          }
        }
      }
      .padding(.bottom, 16)

      // Metadata section with horizontal layout
      HStack(spacing: 32) {
        ForEach(Array(processDetails.enumerated()), id: \.offset) { _, detail in
          if detail.hasPrefix("Category:") || detail.hasPrefix("Severity:") {
            let components = detail.components(separatedBy: ": ")
            if components.count == 2 {
              VStack(alignment: .leading, spacing: 6) {
                Text(components[0].uppercased())
                  .font(.caption2)
                  .fontWeight(.bold)
                  .foregroundColor(.secondary)
                  .tracking(0.8)

                Text(components[1].capitalized)
                  .font(.subheadline)
                  .fontWeight(.semibold)
                  .foregroundColor(components[1] == "error" ? .red : .orange)
              }
            }
          }
        }

        Spacer()
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
  }
}
