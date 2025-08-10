import SwiftUI

struct TestView: View {
    var body: some View {
        VStack {
            Text("Build: \(getBuildTimestamp())")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("Test successful!")
        }
        .padding()
        .frame(width: 300, height: 200)
    }

    private func getBuildTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: Date())
    }
}

@main
struct TestApp: App {
    var body: some Scene {
        WindowGroup {
            TestView()
        }
    }
}
