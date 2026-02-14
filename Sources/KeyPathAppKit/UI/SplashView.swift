import AppKit
import KeyPathCore
import SwiftUI

/// Minimal main-window surface. KeyPath’s primary UI is the live overlay.
struct SplashView: View {
    @State private var posterImage: NSImage? = PosterCache.image()
    @State private var didLogAppear = false

    @MainActor
    enum SplashDiagnostics {
        private static var didLogBody = false

        static func logBodyOnce(posterImage: NSImage?) {
            guard !didLogBody else { return }
            didLogBody = true

            if let posterImage {
                AppLogger.shared.info(
                    "🖼️ [Splash] SplashView.body evaluated with poster (\(Int(posterImage.size.width))x\(Int(posterImage.size.height)))"
                )
            } else {
                AppLogger.shared.warn("🖼️ [Splash] SplashView.body evaluated with poster=nil")
            }
        }
    }

    @MainActor
    enum PosterCache {
        private static var didWarm = false
        private static var cached: NSImage?

        static func warmIfNeeded() {
            guard !didWarm else { return }
            didWarm = true

            // quick-deploy historically didn't sync new resources, so keep a fallback
            // to the older poster name to avoid showing a grey placeholder.
            for candidate in ["keypath-poster-hor", "keypath-poster"] {
                guard let url = Bundle.main.url(forResource: candidate, withExtension: "png") else {
                    continue
                }

                let start = Date()
                if let image = NSImage(contentsOf: url) {
                    // Force decode now so the poster doesn't appear blank during a brief splash.
                    _ = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
                    cached = image
                    let elapsed = Date().timeIntervalSince(start)
                    AppLogger.shared.debug(
                        "🖼️ [Splash] Warmed poster '\(candidate).png' (\(Int(image.size.width))x\(Int(image.size.height))) in \(String(format: "%.3f", elapsed))s"
                    )
                    return
                }
            }

            AppLogger.shared.warn("🖼️ [Splash] Poster not found in Bundle.main resources")
        }

        static func image() -> NSImage? {
            warmIfNeeded()
            return cached
        }
    }

    var body: some View {
        let buildInfo = BuildInfo.current()
        let _ = SplashDiagnostics.logBodyOnce(posterImage: posterImage)
        let debugLayout =
            ProcessInfo.processInfo.environment["KEYPATH_SPLASH_DEBUG_LAYOUT"] == "1"
        let posterTargetWidth: CGFloat = 560
        let posterAspect: CGFloat = {
            guard let image = posterImage, image.size.height > 0 else { return 16.0 / 9.0 }
            return image.size.width / image.size.height
        }()
        let posterTargetHeight = posterTargetWidth / posterAspect

        ZStack {
            // Match the poster background so the window doesn't read as a grey "missing image" panel.
            LinearGradient(
                colors: [
                    Color(red: 0x48 / 255.0, green: 0x4C / 255.0, blue: 0x54 / 255.0),
                    Color(red: 0x1D / 255.0, green: 0x1D / 255.0, blue: 0x21 / 255.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                Image(nsImage: posterImage ?? NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    // Fixed-size splash poster (derived from the image aspect ratio) so it cannot
                    // collapse to an "intrinsic" tiny width during early launch.
                    .frame(width: posterTargetWidth, height: posterTargetHeight)
                    .background(debugLayout ? Color.green.opacity(0.18) : Color.clear)
                    .overlay {
                        if debugLayout {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.pink.opacity(0.85), lineWidth: 2)
                        }
                    }
                    .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 10)
                    .accessibilityIdentifier("main-window-splash-poster")
                    .layoutPriority(1)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 24)

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text("v\(buildInfo.version) (\(buildInfo.build))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.18))
                        .clipShape(Capsule())
                        .accessibilityIdentifier("main-window-splash-build")
                }
                .padding(12)
            }
        }
        .onAppear {
            // In AppKit-hosted SwiftUI, `.task` can be unreliable during early launch.
            // Use `onAppear` so we always force a state refresh when the splash becomes visible.
            PosterCache.warmIfNeeded()
            posterImage = PosterCache.image()

            guard !didLogAppear else { return }
            didLogAppear = true

            if let posterImage {
                AppLogger.shared.info(
                    "🖼️ [Splash] SplashView using poster (\(Int(posterImage.size.width))x\(Int(posterImage.size.height)))"
                )
            } else {
                AppLogger.shared.warn(
                    "🖼️ [Splash] SplashView has no poster image (using app icon fallback)"
                )
            }
        }
        .accessibilityIdentifier("main-window-splash")
    }
}
