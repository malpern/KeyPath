import SwiftUI

/// Splash screen with dark background matching poster
struct SplashView: View {
    // Dark background matching the poster's dark edges
    static let background = Color(red: 30/255, green: 30/255, blue: 34/255)

    var body: some View {
        ZStack {
            // Solid dark background
            Self.background
                .ignoresSafeArea()

            // Horizontal poster image - 500x400 (1000x800 @2x retina)
            if let url = Bundle.main.url(forResource: "keypath-poster-hor", withExtension: "png"),
               let nsImage = NSImage(contentsOf: url)
            {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
            } else {
                // Fallback if image not found
                Text("KeyPath")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
        }
    }
}

#Preview {
    SplashView()
        .frame(width: 500, height: 400)
}
