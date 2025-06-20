import SwiftUI
import AppKit

extension Notification.Name {
    static let newChatRequested = Notification.Name("newChatRequested")
}

@Observable
class MenuBarActions {
    func showSettings() {
        // Open settings window
        SettingsWindowController.shared.showWindow(nil)
    }

    func newChat() {
        // Post notification to reset conversation
        NotificationCenter.default.post(name: .newChatRequested, object: nil)
    }

    func restartKeyPath() {
        // Restart kanata engine
        Task {
            await restartKanataEngine()
        }
    }

    func quitApp() {
        // Stop kanata and quit
        Task {
            await stopKanataEngine()
            await MainActor.run {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func restartKanataEngine() async {
        print("Restarting KeyPath/Kanata engine...")
        // Implementation would restart the kanata process
    }

    private func stopKanataEngine() async {
        print("Stopping KeyPath/Kanata engine...")
        // Implementation would stop the kanata process
    }
}

struct MenuBarView: View {
    let actions = MenuBarActions()

    var body: some View {
        VStack(spacing: 4) {
            MenuBarItem(icon: "square.and.pencil", title: "New Chat") {
                actions.newChat()
            }

            Divider()

            MenuBarItem(icon: "gearshape", title: "Settings") {
                actions.showSettings()
            }

            MenuBarItem(icon: "arrow.clockwise", title: "Restart KeyPath") {
                actions.restartKeyPath()
            }

            Divider()

            MenuBarItem(icon: "power", title: "Quit KeyPath", isDestructive: true) {
                actions.quitApp()
            }
        }
        .padding(.vertical, 4)
    }
}

struct MenuBarItem: View {
    let icon: String
    let title: String
    let isDestructive: Bool
    let action: () -> Void

    init(icon: String, title: String, isDestructive: Bool = false, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.isDestructive = isDestructive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(isDestructive ? .red : .primary)
                    .frame(width: 20)
                Text(title)
                    .foregroundColor(isDestructive ? .red : .primary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { _ in
            // Add hover effect if needed
        }
    }
}
