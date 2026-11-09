import AppKit
import KeyPathCore

enum SystemDiagnostics {
    enum Target {
        case accessibility
        case systemSettings

        fileprivate var url: URL? {
            switch self {
            case .accessibility:
                URL(string: WizardSystemPaths.accessibilitySettings)
            case .systemSettings:
                URL(fileURLWithPath: "/System/Applications/System Settings.app")
            }
        }
    }

    static func open(_ target: Target) {
        guard let url = target.url else { return }
        NSWorkspace.shared.open(url)
    }

    static func openSystemSettings() {
        open(.systemSettings)
    }
}
