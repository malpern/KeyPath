import SwiftUI

struct InstallerView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Installer")
                    .font(.title)

                Text("This installer is not yet implemented.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Text("Please use the command line installer:")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Text("sudo ./install-system.sh install")
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .clipShape(.rect(cornerRadius: 8))

                    Text("This will install Kanata and set up the LaunchDaemon service.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Installer")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 400, height: 300)
    }
}
