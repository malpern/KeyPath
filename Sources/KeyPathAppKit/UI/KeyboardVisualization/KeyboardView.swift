import SwiftUI

/// Main keyboard view that renders all keys using normalized coordinates
struct KeyboardView: View {
    @ObservedObject var viewModel: KeyboardVisualizationViewModel

    var body: some View {
        GeometryReader { geo in
            let unitSize = min(
                geo.size.width / viewModel.layout.totalWidth,
                geo.size.height / viewModel.layout.totalHeight
            )

            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(white: 0.98))
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)

                // Render all keys
                ForEach(viewModel.layout.keys) { key in
                    KeycapView(key: key, isPressed: viewModel.isPressed(key))
                        .frame(
                            width: key.width * unitSize,
                            height: key.height * unitSize
                        )
                        .position(
                            x: (key.x + key.width / 2) * unitSize,
                            y: (key.y + key.height / 2) * unitSize
                        )
                }

                // Close button in top-right corner
                VStack {
                    HStack {
                        Spacer()
                        Button(action: {
                            KeyboardVisualizationManager.shared.hide()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.secondary)
                                .background(Circle().fill(Color(white: 0.98)))
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                    }
                    Spacer()
                }
            }
        }
        .aspectRatio(
            viewModel.layout.totalWidth / viewModel.layout.totalHeight,
            contentMode: .fit
        )
        .padding(16)
    }
}
