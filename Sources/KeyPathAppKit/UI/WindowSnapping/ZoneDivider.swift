import SwiftUI

// MARK: - Zone Divider

struct ZoneDivider: View {
    enum Orientation { case horizontal, vertical }
    let orientation: Orientation

    var body: some View {
        switch orientation {
        case .horizontal:
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 1)
        case .vertical:
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 1)
        }
    }
}
