import SwiftUI

/// Simple UI to run helper cleanup/repair and show step-by-step logs.
struct CleanupAndRepairView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var maintenance = HelperMaintenance.shared
    @State private var started = false
    @State private var succeeded = false
    @State private var useAppleScriptFallback = true
    @State private var duplicateCopies: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cleanup & Repair Privileged Helper")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("Close") { dismiss() }
            }
            .padding(.bottom, 4)

            Text("This will unregister the helper, remove stale artifacts, and re-register it from /Applications/KeyPath.app. You may be prompted for an administrator password.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            // Duplicate copies hint + reveal
            if duplicateCopies.count > 1 {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundColor(.orange)
                    Text("Multiple KeyPath.app copies detected. Remove extras to avoid stale approvals.")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                    Spacer()
                    Button("Reveal Copies") {
                        for p in duplicateCopies {
                            let url = URL(fileURLWithPath: p)
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(maintenance.logLines.indices, id: \.self) { idx in
                        Text(maintenance.logLines[idx])
                            .font(.system(.footnote, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
            )
            .frame(minHeight: 220)

            Toggle("Use Admin Prompt Fallback (AppleScript)", isOn: $useAppleScriptFallback)
                .font(.system(size: 12))

            HStack {
                if maintenance.isRunning {
                    ProgressView().scaleEffect(0.8)
                }
                if started, !maintenance.isRunning {
                    Image(systemName: succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(succeeded ? .green : .red)
                }
                Spacer()
                Button(maintenance.isRunning ? "Working…" : "Run Cleanup") {
                    Task {
                        started = true
                        succeeded = await maintenance.runCleanupAndRepair(useAppleScriptFallback: useAppleScriptFallback)
                    }
                }
                .disabled(maintenance.isRunning)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 360)
        .onAppear {
            duplicateCopies = HelperMaintenance.shared.detectDuplicateAppCopies()
        }
    }
}
