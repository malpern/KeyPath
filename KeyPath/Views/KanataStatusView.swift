import SwiftUI

struct KanataStatusView: View {
    @State private var isKanataRunning = false
    @State private var statusMessage = ""
    
    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(isKanataRunning ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
                .animation(.easeInOut(duration: 0.3), value: isKanataRunning)
            
            // Status text
            Text(statusMessage)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            // Refresh button
            Button(action: checkStatus) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Refresh Kanata status")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.1))
        )
        .onAppear {
            checkStatus()
        }
    }
    
    private func checkStatus() {
        let processManager = KanataProcessManager.shared
        isKanataRunning = processManager.isKanataRunning()
        statusMessage = processManager.getStatusMessage()
        
        DebugLogger.shared.log("🔧 DEBUG: Kanata status check - running: \(isKanataRunning), message: \(statusMessage)")
    }
}

#Preview {
    VStack {
        KanataStatusView()
        Spacer()
    }
    .padding()
}
