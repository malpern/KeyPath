import SwiftUI

// MARK: - Typing Sounds Section

/// Section for selecting typing sound profiles in the overlay drawer
struct TypingSoundsSection: View {
    @ObservedObject private var soundsManager = TypingSoundsManager.shared
    @State private var hoveredProfile: SoundProfile?
    @State private var hoverDebounceTask: Task<Void, Never>?

    let isDark: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            Text("Typing Sounds")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            // Sound profile grid (2 columns)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(SoundProfile.all) { profile in
                    SoundProfileCard(
                        profile: profile,
                        isSelected: soundsManager.selectedProfile.id == profile.id,
                        isHovered: hoveredProfile?.id == profile.id,
                        isDark: isDark,
                        onSelect: {
                            soundsManager.selectedProfile = profile
                        },
                        onHover: { isHovering in
                            handleHover(profile: profile, isHovering: isHovering)
                        }
                    )
                }
            }

            // Description bar (shows hovered or selected profile info)
            SoundProfileDescriptionBar(
                profile: hoveredProfile ?? soundsManager.selectedProfile,
                volume: $soundsManager.volume,
                isDark: isDark
            )
        }
    }

    private func handleHover(profile: SoundProfile, isHovering: Bool) {
        hoverDebounceTask?.cancel()

        if isHovering {
            // Debounce to avoid spamming sounds on quick mouse movements
            hoverDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }

                hoveredProfile = profile
                // Play sample when hovering (not for "Off")
                if profile.id != SoundProfile.off.id {
                    soundsManager.playSample(for: profile)
                }
            }
        } else {
            hoveredProfile = nil
        }
    }
}

// MARK: - Sound Profile Card

private struct SoundProfileCard: View {
    let profile: SoundProfile
    let isSelected: Bool
    let isHovered: Bool
    let isDark: Bool
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                // Icon/color indicator
                ZStack {
                    if profile.id == SoundProfile.off.id {
                        Image(systemName: "speaker.slash.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                    } else {
                        Circle()
                            .fill(Color(nsColor: profile.color))
                            .frame(width: 24, height: 24)
                            .shadow(color: Color(nsColor: profile.color).opacity(0.4), radius: isHovered ? 6 : 2)
                    }
                }
                .frame(height: 28)

                // Short name
                Text(profile.shortName)
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(cardBorder, lineWidth: isSelected ? 2 : 1)
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("overlay-sound-profile-button-\(profile.id)")
        .accessibilityLabel("Select sound profile \(profile.name)")
        .onHover { isHovering in
            onHover(isHovering)
        }
    }

    private var cardBackground: Color {
        if isSelected {
            return isDark
                ? Color.white.opacity(0.12)
                : Color.black.opacity(0.06)
        }
        return isDark
            ? Color.white.opacity(0.05)
            : Color.black.opacity(0.03)
    }

    private var cardBorder: Color {
        if isSelected {
            return Color.accentColor
        }
        return isDark
            ? Color.white.opacity(0.1)
            : Color.black.opacity(0.1)
    }
}

// MARK: - Sound Profile Description Bar

private struct SoundProfileDescriptionBar: View {
    let profile: SoundProfile
    @Binding var volume: Float
    let isDark: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Profile info
            HStack(spacing: 8) {
                // Color dot or icon
                if profile.id == SoundProfile.off.id {
                    Image(systemName: "speaker.slash.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    Circle()
                        .fill(Color(nsColor: profile.color))
                        .frame(width: 12, height: 12)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(profile.descriptor)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            // Volume slider (only show if not "Off")
            if profile.id != SoundProfile.off.id {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    Slider(value: $volume, in: 0 ... 1)
                        .controlSize(.small)

                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
        )
        .animation(.easeInOut(duration: 0.2), value: profile.id)
    }
}

// MARK: - Preview

#Preview {
    VStack {
        TypingSoundsSection(isDark: false)
            .frame(width: 200)
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

        TypingSoundsSection(isDark: true)
            .frame(width: 200)
            .padding()
            .background(Color.black)
    }
}
