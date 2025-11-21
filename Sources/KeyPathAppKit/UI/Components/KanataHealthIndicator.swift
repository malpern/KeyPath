import AppKit
import KeyPathCore
import SwiftUI

/// Health status indicator for Kanata engine monitoring
/// Matches the design language of SystemStatusIndicator
struct KanataHealthIndicator: View {
  @ObservedObject private var errorMonitor = KanataErrorMonitor.shared
  @State private var isHovered = false
  @State private var showingDiagnostics = false

  // MARK: - Constants

  private let indicatorSize: CGFloat = 20
  private let backgroundSize: CGFloat = 28

  var body: some View {
    Button(action: handleClick) {
      ZStack {
        // Background: solid chip for degraded/critical; glass for healthy
        if usesSolidChip {
          Circle()
            .fill(Color(NSColor.textBackgroundColor).opacity(0.95))
            .frame(width: backgroundSize, height: backgroundSize)
            .shadow(color: shadowColor, radius: isHovered ? 3 : 1, x: 0, y: 1)
            .overlay(Circle().stroke(borderColor, lineWidth: 0.5))
        } else {
          AppGlassBackground(style: .chipBold, cornerRadius: backgroundSize / 2)
            .frame(width: backgroundSize, height: backgroundSize)
            .shadow(color: shadowColor, radius: isHovered ? 3 : 1, x: 0, y: 1)
            .overlay(Circle().stroke(borderColor, lineWidth: 0.5))
        }

        // Status icon with badge
        ZStack {
          Image(systemName: iconName)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(iconColor)

          // Unread badge
          if errorMonitor.unreadErrorCount > 0 {
            Circle()
              .fill(Color.red)
              .frame(width: 8, height: 8)
              .offset(x: 8, y: -8)
              .overlay(
                Circle()
                  .stroke(Color(NSColor.controlBackgroundColor), lineWidth: 1)
                  .frame(width: 8, height: 8)
                  .offset(x: 8, y: -8)
              )
          }
        }
        .frame(width: indicatorSize, height: indicatorSize)
      }
    }
    .buttonStyle(.plain)
    .help(tooltip)
    .scaleEffect(isHovered ? 1.1 : 1.0)
    .animation(.easeInOut(duration: 0.15), value: isHovered)
    .onHover { hovering in
      isHovered = hovering
    }
    .accessibilityLabel(accessibilityLabel)
    .accessibilityHint("Click to view Kanata error diagnostics")
    .sheet(isPresented: $showingDiagnostics) {
      KanataHealthDiagnosticsDialog()
    }
  }

  // MARK: - Computed Properties

  private var iconName: String {
    switch errorMonitor.healthStatus {
    case .healthy:
      return "bolt.circle.fill"
    case .degraded:
      return "exclamationmark.triangle.fill"
    case .critical:
      return "exclamationmark.circle.fill"
    }
  }

  private var iconColor: Color {
    switch errorMonitor.healthStatus {
    case .healthy: return .green
    case .degraded: return .orange
    case .critical: return .red
    }
  }

  private var borderColor: Color {
    switch errorMonitor.healthStatus {
    case .healthy: return Color.green.opacity(0.3)
    case .degraded: return Color.orange.opacity(0.3)
    case .critical: return Color.red.opacity(0.3)
    }
  }

  private var shadowColor: Color {
    switch errorMonitor.healthStatus {
    case .healthy: return Color.green.opacity(0.2)
    case .degraded: return Color.orange.opacity(0.2)
    case .critical: return Color.red.opacity(0.2)
    }
  }

  private var usesSolidChip: Bool {
    switch errorMonitor.healthStatus {
    case .healthy: return true
    case .degraded, .critical: return true
    }
  }

  private var tooltip: String {
    let base: String
    switch errorMonitor.healthStatus {
    case .healthy:
      base = "Kanata Engine: Healthy"
    case .degraded(let reason):
      base = "Kanata Engine: \(reason)"
    case .critical(let reason):
      base = "Kanata Engine: Critical - \(reason)"
    }

    if errorMonitor.unreadErrorCount > 0 {
      return "\(base)\n\(errorMonitor.unreadErrorCount) unread error\(errorMonitor.unreadErrorCount == 1 ? "" : "s")\nClick to view diagnostics"
    }
    return "\(base)\nClick to view diagnostics"
  }

  private var accessibilityLabel: String {
    switch errorMonitor.healthStatus {
    case .healthy: return "Kanata engine healthy"
    case .degraded: return "Kanata engine has warnings"
    case .critical: return "Kanata engine has critical errors"
    }
  }

  // MARK: - Actions

  private func handleClick() {
    AppLogger.shared.log("🔍 [KanataHealthIndicator] Health indicator clicked")

    // Provide haptic feedback
    NSHapticFeedbackManager.defaultPerformer.perform(
      .generic,
      performanceTime: .now
    )

    // Mark errors as read
    errorMonitor.markAllAsRead()

    // Toggle diagnostics panel
    showingDiagnostics.toggle()
  }
}

// MARK: - Diagnostics Dialog

/// Full-screen diagnostics dialog showing Kanata engine health
struct KanataHealthDiagnosticsDialog: View {
  @ObservedObject private var errorMonitor = KanataErrorMonitor.shared
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      // Header
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 8) {
            Image(systemName: errorMonitor.healthStatus.icon)
              .foregroundColor(statusColor)
              .font(.system(size: 20))

            Text("Kanata Engine Diagnostics")
              .font(.system(size: 18, weight: .semibold))
          }

          Text(healthStatusText)
            .font(.system(size: 13))
            .foregroundColor(.secondary)
        }

        Spacer()

        Button("Close") {
          dismiss()
        }
        .buttonStyle(.borderless)
      }
      .padding(.bottom, 8)

      Divider()

      // Health Status Card
      HStack(spacing: 12) {
        ZStack {
          Circle()
            .fill(statusColor.opacity(0.15))
            .frame(width: 60, height: 60)

          Image(systemName: errorMonitor.healthStatus.icon)
            .foregroundColor(statusColor)
            .font(.system(size: 28))
        }

        VStack(alignment: .leading, spacing: 4) {
          Text("Current Status")
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.secondary)

          Text(healthStatusText)
            .font(.system(size: 16, weight: .semibold))

          Text(errorMonitor.recentErrors.isEmpty ? "No issues detected" : "\(errorMonitor.recentErrors.count) error\(errorMonitor.recentErrors.count == 1 ? "" : "s") logged")
            .font(.system(size: 12))
            .foregroundColor(.secondary)
        }

        Spacer()

        if !errorMonitor.recentErrors.isEmpty {
          Button("Clear All Errors") {
            errorMonitor.clearErrors()
          }
          .buttonStyle(.bordered)
        }
      }
      .padding(16)
      .background(
        RoundedRectangle(cornerRadius: 8)
          .fill(Color(NSColor.controlBackgroundColor))
      )

      // Error List
      if errorMonitor.recentErrors.isEmpty {
        // Empty state
        VStack(spacing: 16) {
          Spacer()

          Image(systemName: "checkmark.circle")
            .font(.system(size: 64))
            .foregroundColor(.green)

          VStack(spacing: 4) {
            Text("No Errors Detected")
              .font(.system(size: 16, weight: .semibold))

            Text("Kanata engine is running smoothly")
              .font(.system(size: 13))
              .foregroundColor(.secondary)
          }

          Spacer()
        }
        .frame(maxWidth: .infinity)
      } else {
        // Error list header
        Text("Error Log")
          .font(.system(size: 13, weight: .semibold))
          .padding(.top, 8)

        // Scrollable error list
        ScrollView {
          VStack(alignment: .leading, spacing: 10) {
            ForEach(errorMonitor.recentErrors) { error in
              DetailedErrorRow(error: error)
            }
          }
          .padding(.vertical, 4)
        }
        .background(
          RoundedRectangle(cornerRadius: 8)
            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
      }

      Spacer()

      // Footer
      HStack {
        Text("Monitoring Kanata stderr for critical errors")
          .font(.system(size: 11))
          .foregroundColor(.secondary)

        Spacer()

        Button("Open Full Diagnostics") {
          dismiss()
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            openSettings(tab: .advanced)
          }
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .padding(20)
    .frame(minWidth: 600, minHeight: 500)
  }

  private var statusColor: Color {
    switch errorMonitor.healthStatus {
    case .healthy: return .green
    case .degraded: return .orange
    case .critical: return .red
    }
  }

  private var healthStatusText: String {
    switch errorMonitor.healthStatus {
    case .healthy: return "Engine Healthy"
    case .degraded(let reason): return "Warning: \(reason)"
    case .critical(let reason): return "Critical: \(reason)"
    }
  }
}

/// Detailed error row for diagnostics dialog
struct DetailedErrorRow: View {
  let error: KanataError

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      // Header row
      HStack {
        // Severity badge
        HStack(spacing: 4) {
          Image(systemName: error.severity.icon)
            .font(.system(size: 12))
          Text(error.severity.rawValue.uppercased())
            .font(.system(size: 10, weight: .bold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
          RoundedRectangle(cornerRadius: 4)
            .fill(severityColor.opacity(0.2))
        )
        .foregroundColor(severityColor)

        Spacer()

        Text(error.timestampString)
          .font(.system(.caption, design: .monospaced))
          .foregroundColor(.secondary)
      }

      // User message
      Text(error.message)
        .font(.system(size: 13, weight: .medium))
        .fixedSize(horizontal: false, vertical: true)

      // Raw log line
      Text(error.rawLine)
        .font(.system(size: 11, design: .monospaced))
        .foregroundColor(.secondary)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
          RoundedRectangle(cornerRadius: 4)
            .fill(Color(NSColor.textBackgroundColor))
        )
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: 6)
        .fill(Color(NSColor.controlBackgroundColor))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 6)
        .stroke(severityColor.opacity(0.3), lineWidth: 1)
    )
  }

  private var severityColor: Color {
    switch error.severity {
    case .critical: return .red
    case .warning: return .orange
    case .info: return .gray
    }
  }
}

/// Labeled version with text for header integration
struct LabeledKanataHealthIndicator: View {
  var body: some View {
    HStack(spacing: 6) {
      Text("Engine")
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.secondary)

      KanataHealthIndicator()
    }
  }
}

// MARK: - Helper Functions

/// Opens Settings window and navigates to Advanced tab with Errors
@MainActor
private func openSettings(tab: SettingsTab) {
  // Post notification to select Advanced tab
  NotificationCenter.default.post(name: .openSettingsAdvanced, object: nil)

  // Open the Settings window by triggering the Settings menu item
  if let appMenu = NSApp.mainMenu?.items.first?.submenu {
    for item in appMenu.items {
      if item.title.contains("Settings") || item.title.contains("Preferences"),
         let action = item.action
      {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(action, to: item.target, from: item)

        // Switch to Errors tab after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
          NotificationCenter.default.post(name: .showErrorsTab, object: nil)
        }
        return
      }
    }
  }

  // Fallback: Use the selector method
  NSApp.activate(ignoringOtherApps: true)
  if #available(macOS 13, *) {
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
  } else {
    NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
  }

  // Switch to Errors tab after a delay
  DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
    NotificationCenter.default.post(name: .showErrorsTab, object: nil)
  }
}
