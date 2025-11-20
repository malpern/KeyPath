import SwiftUI

struct SetupBanner: View {
  let onCompleteSetup: () -> Void
  @State private var isDismissed = false

  var body: some View {
    if !isDismissed {
      VStack(spacing: 12) {
        HStack {
          Image(systemName: "exclamationmark.circle.fill")
            .foregroundColor(.orange)

          VStack(alignment: .leading, spacing: 4) {
            Text("Complete Setup")
              .font(.headline)
            Text("Grant permissions to enable keyboard remapping")
              .font(.caption)
              .foregroundColor(.secondary)
          }

          Spacer()

          Button("Complete Setup") {
            onCompleteSetup()
          }
          .buttonStyle(.borderedProminent)

          Button {
            isDismissed = true
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundColor(.secondary)
          }
          .buttonStyle(.plain)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
      }
      .padding()
      .transition(.move(edge: .top))
    }
  }
}
