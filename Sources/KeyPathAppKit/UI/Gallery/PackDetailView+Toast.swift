import SwiftUI

// MARK: - Toast overlay

extension PackDetailView {
    @ViewBuilder
    var toastOverlay: some View {
        if let error = errorMessage {
            toastView(
                icon: "exclamationmark.triangle.fill",
                iconColor: .orange,
                message: error,
                action: nil
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .padding(.bottom, 72)
        } else if justInstalled {
            toastView(
                icon: "checkmark.circle.fill",
                iconColor: .green,
                message: installedToastMessage,
                action: ("Undo", { Task { await undoInstall() } })
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .padding(.bottom, 72)
        } else if justUninstalled {
            toastView(
                icon: "checkmark.circle.fill",
                iconColor: .green,
                message: "\(pack.name) turned off.",
                action: ("Undo", { Task { await undoUninstall() } })
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .padding(.bottom, 72)
        }
    }

    var installedToastMessage: String {
        pack.bindings.count == 1
            ? "\(pack.name) turned on."
            : "\(pack.name) turned on · \(pack.bindings.count) bindings added."
    }

    func toastView(
        icon: String,
        iconColor: Color,
        message: String,
        action: (label: String, handler: () -> Void)?
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
            if let action {
                Button(action.label, action: action.handler)
                    .buttonStyle(.link)
                    .foregroundStyle(.blue)
                    .accessibilityIdentifier("pack-detail-banner-action")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.14), radius: 10, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
        )
    }

    func showTemporaryError(_ message: String) {
        withAnimation { errorMessage = message }
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) { errorMessage = nil }
            }
        }
    }
}
