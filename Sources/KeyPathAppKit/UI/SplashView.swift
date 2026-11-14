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
        /// Set only once the poster has loaded: a failed load (for example the
        /// test bundle, which has no poster) may be retried from another bundle.
        private static var didWarm = false
        private static var didWarnMissing = false
        private(set) static var image: NSImage?

        /// Decode the poster before the window shows, so a brief splash is never blank.
        static func warmIfNeeded(bundle: Bundle = .main) {
            guard !didWarm else { return }
            guard let url = bundle.url(forResource: "keypath-poster-hor", withExtension: "png"),
                  let poster = NSImage(contentsOf: url)
            else {
                if !didWarnMissing {
                    didWarnMissing = true
                    AppLogger.shared.warn("🖼️ [Splash] keypath-poster-hor.png not found in the app bundle")
                }
                return
            }
            _ = poster.cgImage(forProposedRect: nil, context: nil, hints: nil)
            image = poster
            didWarm = true
        }
    }

    /// Read once: the splash should not touch the disk each time it redraws.
    private static let buildInfo = BuildInfo.current()

    /// The splash window has the poster's own shape, so the poster fills it edge
    /// to edge. The poster ships at twice this width for Retina.
    static let contentSize = NSSize(width: 640, height: 357)
    private let amber = Color(red: 1, green: 0.61, blue: 0.16)
    private let warmGray = Color(red: 0.76, green: 0.74, blue: 0.70)

    var body: some View {
        let buildInfo = Self.buildInfo
        ZStack {
            // Behind the poster, and the whole background if it failed to load.
            LinearGradient(
                colors: [KeyPathColors.splashGradientTop, KeyPathColors.splashGradientBottom],
                startPoint: .top,
                endPoint: .bottom
            )

            poster
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .accessibilityLabel("KeyPath")
                .accessibilityIdentifier("main-window-splash-poster")

            // Status sits on the poster's empty lower band, not below it.
            VStack(spacing: 0) {
                Spacer()
                if presentation.isPreparing {
                    HStack(spacing: 10) {
                        TimelineView(.animation(minimumInterval: 0.55, paused: reduceMotion)) { context in
                            let active = reduceMotion ? 1 : Int(context.date.timeIntervalSinceReferenceDate / 0.55) % 3
                            HStack(spacing: 6) {
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
                    .padding(.bottom, 22)
                }
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text(verbatim: "v\(buildInfo.version) (\(buildInfo.build))")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(warmGray.opacity(0.8))
                        .accessibilityIdentifier("main-window-splash-build")
                }
                .padding(.trailing, 18)
                .padding(.bottom, 14)
            }
        }
        // The window takes its size from this view, so it must ask for its full
        // size; a view that only fills what it is given shrinks the window.
        .frame(width: Self.contentSize.width, height: Self.contentSize.height)
        .ignoresSafeArea()
        .onAppear { PosterCache.warmIfNeeded() }
        .accessibilityIdentifier("main-window-splash")
    }

    @ViewBuilder
    private var poster: some View {
        if let image = PosterCache.image {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
        } else {
            Image(systemName: "keyboard").resizable().scaledToFit()
                .foregroundStyle(.white.opacity(0.85))
                .padding(80)
        }
    }
}
