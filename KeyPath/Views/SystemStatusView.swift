import SwiftUI

struct SystemStatusView: View {
    @ObservedObject var securityManager: SecurityManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("System Status")
                .font(.headline)
            
            StatusRow(
                title: "Kanata Installation", 
                status: securityManager.isKanataInstalled,
                icon: "cpu"
            )
            
            StatusRow(
                title: "Configuration Access", 
                status: securityManager.hasConfigAccess,
                icon: "folder"
            )
            
            StatusRow(
                title: "Ready to Install Rules", 
                status: securityManager.canInstallRules(),
                icon: "checkmark.circle"
            )
            
            Button("Refresh Status") {
                securityManager.forceRefresh()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

struct StatusRow: View {
    let title: String
    let status: Bool
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(status ? .green : .red)
                .frame(width: 20)
            
            Text(title)
            
            Spacer()
            
            Image(systemName: status ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(status ? .green : .red)
        }
    }
}
