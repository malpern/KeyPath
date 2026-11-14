import AppKit
import KeyPathCore
import Observation
import SwiftUI

/// The same window also hosts menu-action sheets, which must not look busy.
@MainActor
@Observable
final class SplashPresentation {
    var isPreparing = true
}

/// The launch splash: the KeyPath poster on its dark gradient, with activity
/// shown only while first-run setup is being prepared.
struct SplashView: View {
    @Environment(SplashPresentation.self) private var presentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @MainActor
    enum PosterCache {
        private static var didWarm = false
        private(set) static var image: NSImage?

        /// Decode the poster before the window shows, so a brief splash is never blank.
        static func warmIfNeeded(bundle: Bundle = .main) {
            guard !didWarm else { return }
            didWarm = true
            guard let url = bundle.url(forResource: "keypath-poster-hor", withExtension: "png"),
                  let poster = NSImage(contentsOf: url)
            else {
                AppLogger.shared.warn("🖼️ [Splash] keypath-poster-hor.png not found in the app bundle")
                return
            }
            _ = poster.cgImage(forProposedRect: nil, context: nil, hints: nil)
            image = poster
        }
    }

    /// The poster is drawn at a fixed width so it cannot collapse during early launch.
    private let posterWidth: CGFloat = 560
    private let amber = Color(red: 1, green: 0.61, blue: 0.16)
    private let warmGray = Color(red: 0.76, green: 0.74, blue: 0.70)

    var body: some View {
        let buildInfo = BuildInfo.current()
        ZStack {
            // Matches the poster's own background, so the edges never read as a frame.
            LinearGradient(
                colors: [KeyPathColors.splashGradientTop, KeyPathColors.splashGradientBottom],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 0) {
                Spacer(minLength: 24)
                poster
                    .frame(width: posterWidth, height: posterWidth / posterAspect)
                    .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 10)
                    .accessibilityLabel("KeyPath")
                    .accessibilityIdentifier("main-window-splash-poster")
                Spacer(minLength: 16)
                if presentation.isPreparing {
                    VStack(spacing: 10) {
                        TimelineView(.animation(minimumInterval: 0.55, paused: reduceMotion)) { context in
                            let active = reduceMotion ? 1 : Int(context.date.timeIntervalSinceReferenceDate / 0.55) % 3
                            HStack(spacing: 7) {
                                ForEach(0 ..< 3) { index in
                                    Circle().fill(amber.opacity(index == active ? 1 : 0.3))
                                        .frame(width: 5, height: 5)
                                }
                            }
                        }
                        .accessibilityHidden(true)
                        Text("Getting your keyboard ready…")
                            .font(.system(size: 12))
                            .foregroundStyle(warmGray)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("main-window-splash-loading")
                    .padding(.bottom, 28)
                } else {
                    // Keep the poster in place when a menu action presents a sheet.
                    Spacer().frame(height: 56)
                }
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text(verbatim: "v\(buildInfo.version) (\(buildInfo.build))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.4), in: Capsule())
                        .accessibilityIdentifier("main-window-splash-build")
                }
                .padding(12)
            }
        }
        .ignoresSafeArea()
        .onAppear { PosterCache.warmIfNeeded() }
        .accessibilityIdentifier("main-window-splash")
    }

    private var posterAspect: CGFloat {
        guard let size = PosterCache.image?.size, size.height > 0 else { return 1120.0 / 625.0 }
        return size.width / size.height
    }

    @ViewBuilder
    private var poster: some View {
        if let image = PosterCache.image {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
        } else {
            Image(nsImage: NSApp.applicationIconImage).resizable().scaledToFit()
        }
    }
}
