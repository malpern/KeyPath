import SwiftUI

struct RootView: View {
  var body: some View {
    ZStack {
      // Full-window glass background; we can dial this back per-surface
      AppGlassBackground(style: .sheetBold)
        .ignoresSafeArea()

      // Foreground content places solid surfaces where needed for text
      ContentView()
    }
  }
}
