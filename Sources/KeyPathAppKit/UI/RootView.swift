import SwiftUI

struct RootView: View {
    @State private var showingWhatsNew = false

    var body: some View {
        ZStack {
            // Full-window glass background; we can dial this back per-surface
            AppGlassBackground(style: .sheetBold)
                .ignoresSafeArea()

            // Foreground content places solid surfaces where needed for text
            ContentView()
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: WindowHeightPreferenceKey.self, value: proxy.size.height)
                    }
                )
        }
        .sheet(isPresented: $showingWhatsNew) {
            WhatsNewView()
                .onDisappear {
                    WhatsNewTracker.markAsSeen()
                }
        }
        .onPreferenceChange(WindowHeightPreferenceKey.self) { newHeight in
            guard newHeight > 0 else { return }
            NotificationCenter.default.post(
                name: .mainWindowHeightChanged,
                object: nil,
                userInfo: ["height": newHeight]
            )
        }
        .task {
            if WhatsNewTracker.shouldShowWhatsNew() {
                showingWhatsNew = true
            }
        }
    }
}
