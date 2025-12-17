import AppKit
import KeyPathCore

struct SystemDiagnostics {
    enum Target {
        case loginItems
        case inputMonitoring
        case accessibility
        case fullDiskAccess
        case systemSettings

        fileprivate var url: URL? {
            switch self {
            case .loginItems:
                return URL(string: WizardSystemPaths.loginItemsSettings)
            case .inputMonitoring:
                return URL(string: WizardSystemPaths.inputMonitoringSettings)
            case .accessibility:
                return URL(string: WizardSystemPaths.accessibilitySettings)
            case .fullDiskAccess:
                return URL(string: WizardSystemPaths.fullDiskAccessSettings)
            case .systemSettings:
                return URL(fileURLWithPath: "/System/Applications/System Settings.app")
            }
        }
    }

    static func open(_ target: Target) {
        guard let url = target.url else { return }
        NSWorkspace.shared.open(url)
    }

    static func openKanataLogsInEditor() {
        let url = URL(fileURLWithPath: KeyPathConstants.Logs.kanataStderr)
        Task { @MainActor in
            openFileInPreferredEditor(url)
        }
    }

    static func openKarabinerLogsDirectory() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: KeyPathConstants.Logs.karabinerDir)
    }

    static func openSystemSettings() {
        open(.systemSettings)
    }
}
