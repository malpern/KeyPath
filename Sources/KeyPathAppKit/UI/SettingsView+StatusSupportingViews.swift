import KeyPathPermissions
import SwiftUI

struct PermissionStatusRow: View {
    let title: String
    let icon: String
    let status: PermissionOracle.Status?
    let isKanata: Bool
    let hasFullDiskAccess: Bool
    let onTap: (() -> Void)?

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundColor(statusColor)
                    .frame(width: 20)

                Text(title)
                    .font(.body)

                Spacer()

                if status != nil {
                    Image(systemName: trailingIcon)
                        .foregroundColor(trailingColor)
                        .font(.body)
                } else {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
        .accessibilityIdentifier("settings-status-action-button-\(title.lowercased().replacingOccurrences(of: " ", with: "-"))")
        .accessibilityLabel(title)
    }

    private var statusColor: Color {
        guard let status else { return .secondary }
        switch status {
        case .granted:
            return .green
        case .denied, .error:
            return .red
        case .unknown:
            // For Kanata, unknown is commonly due to missing Full Disk Access (TCC not readable).
            // For KeyPath, unknown is usually a transient "still checking" (startup mode).
            return isKanata ? .orange : .secondary
        }
    }

    private var trailingIcon: String {
        guard let status else { return "ellipsis.circle" }
        switch status {
        case .granted:
            return "checkmark.circle.fill"
        case .denied, .error:
            return "xmark.circle.fill"
        case .unknown:
            if isKanata, !hasFullDiskAccess {
                return "questionmark.circle.fill"
            }
            return "questionmark.circle"
        }
    }

    private var trailingColor: Color {
        guard let status else { return .secondary }
        switch status {
        case .granted:
            return .green
        case .denied, .error:
            return .red
        case .unknown:
            return isKanata ? .orange : .secondary
        }
    }
}

struct StatusDetailAction: Identifiable {
    let id = UUID()
    let title: String
    let icon: String?
    let handler: () -> Void
}

struct StatusDetail: Identifiable {
    enum Level: Int {
        case success = 0
        case info = 1
        case warning = 2
        case critical = 3
    }

    let title: String
    let message: String
    let icon: String
    let level: Level
    let actions: [StatusDetailAction]

    var id: String {
        "\(title)|\(message)"
    }

    init(
        title: String,
        message: String,
        icon: String,
        level: Level,
        actions: [StatusDetailAction] = []
    ) {
        self.title = title
        self.message = message
        self.icon = icon
        self.level = level
        self.actions = actions
    }
}

extension StatusDetail.Level {
    var tintColor: Color {
        switch self {
        case .success: .green
        case .info: .secondary
        case .warning: .orange
        case .critical: .red
        }
    }

    var isIssue: Bool {
        switch self {
        case .warning, .critical: true
        case .success, .info: false
        }
    }
}

struct StatusDetailRow: View {
    let detail: StatusDetail

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: detail.icon)
                .foregroundColor(detail.level.tintColor)
                .font(.body)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(detail.title)
                    .font(.subheadline.weight(.semibold))

                Text(detail.message)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if !detail.actions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(detail.actions) { action in
                        Button {
                            action.handler()
                        } label: {
                            if let icon = action.icon {
                                Label(action.title, systemImage: icon)
                                    .labelStyle(.titleAndIcon)
                            } else {
                                Text(action.title)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("status-action-\(action.title.lowercased().replacingOccurrences(of: " ", with: "-"))")
                        .accessibilityLabel(action.title)
                    }
                }
            }
        }
    }
}
