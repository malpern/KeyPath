import SwiftUI

struct PermissionCard: View {
  let appName: String
  let appPath: String
  let status: InstallationStatus
  let permissionType: String

  var body: some View {
    HStack(spacing: 16) {
      statusIcon
        .frame(width: 30)

      VStack(alignment: .leading, spacing: 4) {
        Text(appName)
          .font(.headline)
        Text(appPath)
          .font(.caption)
          .foregroundColor(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }

      Spacer()

      HStack(spacing: 8) {
        Text(statusText)
          .font(.caption)
          .fontWeight(.medium)
          .foregroundColor(statusColor)

        if status == .notStarted {
          Button("Add") {
            openSystemPreferences()
          }
          .buttonStyle(.bordered)
          .controlSize(.mini)
          .help("Click to open System Settings")
        }
      }
    }
    .padding()
    .background(backgroundColor)
    .cornerRadius(8)
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(borderColor, lineWidth: 1)
    )
    .onTapGesture {
      if status == .notStarted {
        openSystemPreferences()
      }
    }
  }

  var statusIcon: some View {
    Group {
      switch status {
      case .completed:
        Image(systemName: "checkmark.circle.fill")
          .foregroundColor(.green)
          .font(.title3)
      case .inProgress:
        ProgressView()
          .scaleEffect(0.7)
      case .failed:
        Image(systemName: "xmark.circle.fill")
          .foregroundColor(.red)
          .font(.title3)
      case .notStarted:
        Image(systemName: "minus.circle.fill")
          .foregroundColor(.orange)
          .font(.title3)
      }
    }
  }

  var statusText: String {
    switch status {
    case .completed: return "Granted"
    case .inProgress: return "Checking..."
    case .failed: return "Error"
    case .notStarted: return "Not Granted"
    }
  }

  var statusColor: Color {
    switch status {
    case .completed: return .green
    case .inProgress: return .blue
    case .failed: return .red
    case .notStarted: return .orange
    }
  }

  var backgroundColor: Color {
    switch status {
    case .completed: return Color.green.opacity(0.1)
    case .failed: return Color.red.opacity(0.1)
    default: return Color(NSColor.controlBackgroundColor)
    }
  }

  var borderColor: Color {
    switch status {
    case .completed: return Color.green.opacity(0.3)
    case .failed: return Color.red.opacity(0.3)
    case .notStarted: return Color.orange.opacity(0.3)
    default: return Color.clear
    }
  }

  private func openSystemPreferences() {
    if permissionType == "Input Monitoring" {
      // Press Escape to close the wizard for Input Monitoring
      let escapeEvent = NSEvent.keyEvent(
        with: .keyDown,
        location: NSPoint.zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "\u{1b}",
        charactersIgnoringModifiers: "\u{1b}",
        isARepeat: false,
        keyCode: 53
      )

      if let event = escapeEvent {
        NSApplication.shared.postEvent(event, atStart: false)
      }

      // Small delay to ensure wizard closes before opening settings
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        if let url = URL(
          string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        {
          NSWorkspace.shared.open(url)
        }
      }
    } else if permissionType == "Accessibility" {
      // For Accessibility, open settings immediately without closing wizard
      if let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
      {
        NSWorkspace.shared.open(url)
      }
    } else if permissionType == "Background Services" {
      // For Background Services, open both System Settings and Finder
      // First open System Settings
      if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
      {
        NSWorkspace.shared.open(url)
      }

      // Then open Karabiner folder in Finder after a short delay
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        let karabinerPath = "/Library/Application Support/org.pqrs/Karabiner-Elements/"
        if let url = URL(
          string:
            "file://\(karabinerPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? karabinerPath)"
        ) {
          NSWorkspace.shared.open(url)
        }
      }
    } else {
      // Fallback to general Privacy & Security (without closing wizard)
      if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
        NSWorkspace.shared.open(url)
      }
    }
  }
}
