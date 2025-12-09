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
        }
        .sheet(isPresented: $showingWhatsNew) {
            WhatsNewView()
                .onDisappear {
                    WhatsNewTracker.markAsSeen()
                }
        }
        .task {
            if WhatsNewTracker.shouldShowWhatsNew() {
                showingWhatsNew = true
            }
        }
    }
}
