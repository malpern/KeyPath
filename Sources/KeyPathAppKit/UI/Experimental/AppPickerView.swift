import AppKit
import SwiftUI

// MARK: - App Picker View

struct AppPickerView: View {
    let onSelect: (CapturedInput.AppInput) -> Void

    @State private var searchText = ""

    private var apps: [CapturedInput.AppInput] {
        let workspace = NSWorkspace.shared
        var result: [CapturedInput.AppInput] = []

        // Add some common apps
        let commonApps = [
            "/Applications/Safari.app",
            "/Applications/Mail.app",
            "/Applications/Notes.app",
            "/Applications/Calendar.app",
            "/Applications/Messages.app",
            "/Applications/Music.app",
            "/Applications/Finder.app",
            "/System/Applications/Terminal.app",
            "/Applications/Slack.app",
            "/Applications/Visual Studio Code.app",
            "/Applications/Obsidian.app"
        ]

        for path in commonApps {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                let name = url.deletingPathExtension().lastPathComponent
                let bundleID = Bundle(url: url)?.bundleIdentifier ?? ""
                let icon = workspace.icon(forFile: path)
                result.append(CapturedInput.AppInput(name: name, bundleIdentifier: bundleID, icon: icon))
            }
        }

        if searchText.isEmpty {
            return result
        }
        return result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search apps...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // App list
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(apps) { app in
                        Button {
                            onSelect(app)
                        } label: {
                            HStack(spacing: 10) {
                                if let icon = app.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 24, height: 24)
                                }
                                Text(app.name)
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(Color.clear)
                        .cornerRadius(6)
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 250, height: 300)
    }
}
