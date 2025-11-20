import SwiftUI

/// Reusable sheet to present recent helper logs
struct HelperLogsView: View {
  let lines: [String]
  var onClose: (() -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Recent Helper Logs")
        .font(.headline)
      ScrollView {
        Text(lines.isEmpty ? "No recent helper logs" : lines.joined(separator: "\n"))
          .font(.system(.body, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      HStack {
        Spacer()
        Button("Close") { onClose?() }
      }
    }
    .padding()
    .frame(width: 560, height: 360)
  }
}
