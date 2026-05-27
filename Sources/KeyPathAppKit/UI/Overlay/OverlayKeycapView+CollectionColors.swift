import SwiftUI

extension OverlayKeycapView {
    func collectionColor(for collectionId: UUID?) -> Color {
        KeycapSymbols.collectionColor(for: collectionId)
    }
}
