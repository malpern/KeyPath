import AppKit
import Observation
import SwiftUI

/// The same window also hosts menu-action sheets, which must not look busy.
@MainActor
@Observable
final class SplashPresentation {
    var isPreparing = true
}

/// A stable brand lockup, with activity shown only during the launch handoff.
struct SplashView: View {
    @Environment(SplashPresentation.self) private var presentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glowing = false

    @MainActor
    enum EmblemCache {
        private static var didWarm = false
        private(set) static var image: NSImage?

        static func warmIfNeeded() {
            guard !didWarm else { return }
            didWarm = true
            guard let url = Bundle.main.url(forResource: "keypath-splash-emblem", withExtension: "png"),
                  let emblem = NSImage(contentsOf: url) else { return }
            _ = emblem.cgImage(forProposedRect: nil, context: nil, hints: nil)
            image = emblem
        }
    }

    private let ivory = Color(red: 0.97, green: 0.95, blue: 0.90)
    private let warmGray = Color(red: 0.76, green: 0.74, blue: 0.70)
    private let amber = Color(red: 1, green: 0.61, blue: 0.16)

    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.035, blue: 0.045)
            RadialGradient(
                colors: [amber.opacity(0.065), .clear],
                center: .init(x: 0.5, y: 0.43), startRadius: 12, endRadius: 205
            )
            VStack(spacing: 0) {
                Spacer().frame(height: 58)
                emblem
                    .frame(width: 204, height: 158)
                    .shadow(color: amber.opacity(glowing ? 0.16 : 0.07), radius: glowing ? 18 : 12)
                    .animation(
                        reduceMotion || !presentation.isPreparing ? nil :
                            .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                        value: glowing
                    )
                    .accessibilityHidden(true)
                Text("KeyPath")
                    .font(.system(size: 46, weight: .medium, design: .serif))
                    .foregroundStyle(ivory)
                    .padding(.top, 12)
                Text("Keys that do more.")
                    .font(.system(size: 14))
                    .foregroundStyle(warmGray)
                    .padding(.top, 6)
                Spacer(minLength: 24)
                if presentation.isPreparing {
                    VStack(spacing: 12) {
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
                    .padding(.bottom, 32)
                } else {
                    // Keep the lockup in place when a menu action presents a sheet.
                    Spacer().frame(height: 62)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            EmblemCache.warmIfNeeded()
            glowing = true
        }
        .onChange(of: presentation.isPreparing) { _, preparing in
            glowing = preparing
        }
        .accessibilityIdentifier("main-window-splash")
    }

    @ViewBuilder
    private var emblem: some View {
        if let image = EmblemCache.image {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
        } else {
            Image(systemName: "keyboard").font(.system(size: 78)).foregroundStyle(amber)
        }
    }
}
