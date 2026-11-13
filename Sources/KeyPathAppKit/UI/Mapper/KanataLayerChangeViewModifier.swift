import SwiftUI

extension View {
    func onKanataLayerChange(perform action: @escaping @MainActor (KanataLayerChange) -> Void) -> some View {
        modifier(KanataLayerChangeViewModifier(action: action))
    }
}

private struct KanataLayerChangeViewModifier: ViewModifier {
    let action: @MainActor (KanataLayerChange) -> Void
    @State private var observer: NotificationCenter.ObservationToken?

    func body(content: Content) -> some View {
        content
            .onAppear {
                observer = NotificationCenter.default.addObserver(for: KanataLayerChange.self, using: action)
            }
            .onDisappear {
                observer = nil
            }
    }
}
