import SwiftUI

/// Shows "What's New" after an app update
///
/// Checks UserDefaults for the last-seen version and shows this view
/// when the app version has changed (indicating an update).
struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss

    private let version: String
    private let features: [Feature]

    struct Feature: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let description: String
    }

    init() {
        version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        features = Self.featuresForVersion(version)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 44))
                    .foregroundStyle(.blue)
                    .symbolEffect(.pulse)

                Text("What's New in KeyPath")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Version \(version)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 32)
            .padding(.bottom, 24)

            // Features list
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(features) { feature in
                        FeatureRow(feature: feature)
                    }
                }
                .padding(.horizontal, 24)
            }
            .frame(maxHeight: 280)

            Spacer(minLength: 16)

            // Continue button
            Button(action: { dismiss() }) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(width: 400, height: 480)
        .background(.ultraThinMaterial)
    }

    private static func featuresForVersion(_ version: String) -> [Feature] {
        // Return features based on version
        // Expand this as we cut releases.
        if version.contains("beta2") || version == "1.0.0-beta2" {
            return [
                Feature(
                    icon: "eye",
                    title: "Input Monitoring Fix",
                    description: "Setup now correctly guides you to grant Input Monitoring for the exact Kanata binary KeyPath runs, so remaps work reliably."
                ),
                Feature(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Automatic Updates",
                    description: "KeyPath updates itself. You'll be notified when new versions are available."
                ),
                Feature(
                    icon: "wand.and.stars",
                    title: "Installation Wizard",
                    description: "Step-by-step setup guides you through permissions and driver installation."
                )
            ]
        }

        if version.contains("beta1") || version == "1.0.0-beta1" {
            return [
                Feature(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Automatic Updates",
                    description: "KeyPath now updates itself. You'll be notified when new versions are available."
                ),
                Feature(
                    icon: "wand.and.stars",
                    title: "Installation Wizard",
                    description: "Step-by-step setup guides you through permissions and driver installation."
                ),
                Feature(
                    icon: "keyboard",
                    title: "Custom Rules Editor",
                    description: "Create your own keyboard remappings with the built-in config editor."
                ),
                Feature(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "Real-time Feedback",
                    description: "TCP integration with Kanata for instant layer status updates."
                )
            ]
        }

        // Default/unknown version
        return [
            Feature(
                icon: "star.fill",
                title: "Bug Fixes & Improvements",
                description: "This update includes various bug fixes and performance improvements."
            )
        ]
    }
}

private struct FeatureRow: View {
    let feature: WhatsNewView.Feature

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: feature.icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(feature.title)
                    .font(.headline)

                Text(feature.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Version Tracking

enum WhatsNewTracker {
    private static let lastSeenVersionKey = "KeyPath.lastSeenVersion"

    /// Returns true if What's New should be shown (version changed since last launch)
    static func shouldShowWhatsNew() -> Bool {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let lastSeenVersion = UserDefaults.standard.string(forKey: lastSeenVersionKey)

        // First launch ever - don't show What's New, just record version
        guard let lastSeen = lastSeenVersion else {
            markAsSeen()
            return false
        }

        // Version changed - show What's New
        return lastSeen != currentVersion
    }

    /// Mark current version as seen (call after showing What's New or on first launch)
    static func markAsSeen() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        UserDefaults.standard.set(currentVersion, forKey: lastSeenVersionKey)
    }
}

#Preview {
    WhatsNewView()
}
