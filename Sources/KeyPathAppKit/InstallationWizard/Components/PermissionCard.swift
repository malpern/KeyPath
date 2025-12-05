import AppKit
import Foundation
import KeyPathCore
import KeyPathWizardCore
import SwiftUI

struct PermissionCard: View {
    let appName: String
    let appPath: String
    let status: InstallationStatus
    let permissionType: String
    let kanataManager: RuntimeCoordinator

    // Fixed trailing area width so status icons/buttons align across rows
    private let trailingAreaWidth: CGFloat = 160

    var body: some View {
        HStack(spacing: 12) {
            appIcon
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(appName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(appPath)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            trailingStatusView
                .frame(width: trailingAreaWidth, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
        .cornerRadius(10)
        .contentShape(Rectangle())
        .onTapGesture {
            if status == .notStarted {
                openSystemPreferences()
            }
        }
    }

    @ViewBuilder
    private var trailingStatusView: some View {
        switch status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 16, weight: .semibold))
                .accessibilityLabel("Granted")
        case .inProgress:
            ProgressView()
                .scaleEffect(0.7)
                .accessibilityLabel("Checking")
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 16, weight: .semibold))
                .accessibilityLabel("Warning")
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 16, weight: .semibold))
                .accessibilityLabel("Error")
        case .notStarted:
            HStack(spacing: 8) {
                Button("Add…") {
                    openSystemPreferences()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Open System Settings to grant access")
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: 16, weight: .semibold))
                    .accessibilityHidden(true)
            }
        }
    }

    private var appIcon: some View {
        let nsImage = NSWorkspace.shared.icon(forFile: appPath)
        let sized = NSImage(size: NSSize(width: 20, height: 20))
        sized.lockFocus()
        nsImage.draw(in: NSRect(x: 0, y: 0, width: 20, height: 20))
        sized.unlockFocus()
        return Image(nsImage: sized)
            .renderingMode(.original)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // status text and colors removed to avoid duplicate, wordy indicators

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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if let url = URL(
                    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                    NSWorkspace.shared.open(url)
                }

                // Reveal kanata binary in Finder shortly after opening settings (always reveal kanata)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    kanataManager.revealKanataInFinder()
                }
            }
        } else if permissionType == "Accessibility" {
            // For Accessibility, open settings immediately without closing wizard
            if let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        } else if permissionType == "Background Services" {
            // For Background Services, open both System Settings and Finder
            // First open System Settings
            if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
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
