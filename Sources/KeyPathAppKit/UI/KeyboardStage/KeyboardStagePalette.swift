import SwiftUI

struct KeyboardStageRGBA: Equatable, Sendable {
    var red: Float
    var green: Float
    var blue: Float
    var alpha: Float

    init(_ red: Float, _ green: Float, _ blue: Float, _ alpha: Float = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    var color: Color {
        Color(
            .sRGB,
            red: Double(red),
            green: Double(green),
            blue: Double(blue),
            opacity: Double(alpha)
        )
    }

    func interpolated(to destination: Self, progress: Float) -> Self {
        let amount = min(1, max(0, progress))
        return Self(
            red + (destination.red - red) * amount,
            green + (destination.green - green) * amount,
            blue + (destination.blue - blue) * amount,
            alpha + (destination.alpha - alpha) * amount
        )
    }
}

struct KeyboardStageSurfaceStyle: Equatable, Sendable {
    var fill: KeyboardStageRGBA
    var accent: KeyboardStageRGBA
    var glow: KeyboardStageRGBA
    var legend: KeyboardStageRGBA
    var borderStrength: Float

    init(
        fill: KeyboardStageRGBA,
        accent: KeyboardStageRGBA,
        glow: KeyboardStageRGBA? = nil,
        legend: KeyboardStageRGBA,
        borderStrength: Float
    ) {
        self.fill = fill
        self.accent = accent
        self.glow = glow ?? accent
        self.legend = legend
        self.borderStrength = borderStrength
    }
}

struct KeyboardStagePalette: Equatable, Sendable {
    let displayMode: KeyboardStageDisplayMode

    var backgroundTop: KeyboardStageRGBA {
        switch displayMode.appearance {
        case .light:
            KeyboardStageRGBA(0.969, 0.965, 0.965)
        case .dark:
            KeyboardStageRGBA(0.10, 0.11, 0.14)
        }
    }

    var backgroundBottom: KeyboardStageRGBA {
        switch displayMode.appearance {
        case .light:
            KeyboardStageRGBA(0.957, 0.949, 0.949)
        case .dark:
            KeyboardStageRGBA(0.055, 0.06, 0.08)
        }
    }

    func style(for role: KeyboardStageKeyRole) -> KeyboardStageSurfaceStyle {
        let style = switch displayMode.appearance {
        case .light:
            lightStyle(for: role)
        case .dark:
            darkStyle(for: role)
        }

        guard displayMode.increaseContrast else { return style }
        var contrasted = style
        contrasted.borderStrength = min(1, style.borderStrength + 0.3)
        contrasted.legend = displayMode.appearance == .light
            ? KeyboardStageRGBA(0.06, 0.065, 0.075)
            : KeyboardStageRGBA(1, 1, 1)
        return contrasted
    }

    private func lightStyle(for role: KeyboardStageKeyRole) -> KeyboardStageSurfaceStyle {
        switch role {
        case .deck:
            KeyboardStageSurfaceStyle(
                fill: KeyboardStageRGBA(0.965, 0.961, 0.957),
                accent: KeyboardStageRGBA(0.60, 0.585, 0.57),
                legend: KeyboardStageRGBA(0.337, 0.333, 0.329),
                borderStrength: 0.48
            )
        case .standard:
            KeyboardStageSurfaceStyle(
                fill: KeyboardStageRGBA(0.933, 0.929, 0.921),
                accent: KeyboardStageRGBA(0.56, 0.545, 0.53),
                legend: KeyboardStageRGBA(0.337, 0.333, 0.329),
                borderStrength: 0.52
            )
        case .modifier:
            KeyboardStageSurfaceStyle(
                fill: KeyboardStageRGBA(0.937, 0.933, 0.925),
                accent: KeyboardStageRGBA(0.56, 0.545, 0.53),
                legend: KeyboardStageRGBA(0.337, 0.333, 0.329),
                borderStrength: 0.54
            )
        case .recommended:
            KeyboardStageSurfaceStyle(
                fill: KeyboardStageRGBA(0.875, 0.91, 0.929),
                accent: KeyboardStageRGBA(0.439, 0.561, 0.631),
                glow: KeyboardStageRGBA(0.263, 0.655, 0.902),
                legend: KeyboardStageRGBA(0.337, 0.416, 0.467),
                borderStrength: 0.52
            )
        case .escape:
            KeyboardStageSurfaceStyle(
                fill: KeyboardStageRGBA(0.835, 0.882, 0.918),
                accent: KeyboardStageRGBA(0.38, 0.50, 0.57),
                glow: KeyboardStageRGBA(0.263, 0.655, 0.902),
                legend: KeyboardStageRGBA(0.337, 0.416, 0.467),
                borderStrength: 0.68
            )
        case .hyper:
            KeyboardStageSurfaceStyle(
                fill: KeyboardStageRGBA(0.855, 0.89, 0.929),
                accent: KeyboardStageRGBA(0.455, 0.549, 0.663),
                glow: KeyboardStageRGBA(0.302, 0.518, 0.847),
                legend: KeyboardStageRGBA(0.306, 0.376, 0.463),
                borderStrength: 0.56
            )
        case .launcher:
            KeyboardStageSurfaceStyle(
                fill: KeyboardStageRGBA(0.855, 0.914, 0.925),
                accent: KeyboardStageRGBA(0.404, 0.60, 0.647),
                glow: KeyboardStageRGBA(0.263, 0.655, 0.902),
                legend: KeyboardStageRGBA(0.251, 0.373, 0.396),
                borderStrength: 0.52
            )
        case .installed:
            KeyboardStageSurfaceStyle(
                fill: KeyboardStageRGBA(0.863, 0.91, 0.925),
                accent: KeyboardStageRGBA(0.404, 0.576, 0.647),
                glow: KeyboardStageRGBA(0.263, 0.655, 0.902),
                legend: KeyboardStageRGBA(0.278, 0.376, 0.416),
                borderStrength: 0.48
            )
        case .dimmed:
            KeyboardStageSurfaceStyle(
                fill: KeyboardStageRGBA(0.933, 0.929, 0.921),
                accent: KeyboardStageRGBA(0.55, 0.54, 0.52),
                legend: KeyboardStageRGBA(0.294, 0.29, 0.286),
                borderStrength: 0.46
            )
        }
    }

    private func darkStyle(for role: KeyboardStageKeyRole) -> KeyboardStageSurfaceStyle {
        switch role {
        case .deck:
            KeyboardStageSurfaceStyle(
                fill: KeyboardStageRGBA(0.075, 0.08, 0.10),
                accent: KeyboardStageRGBA(0.30, 0.34, 0.43),
                legend: KeyboardStageRGBA(0.88, 0.93, 1),
                borderStrength: 0.26
            )
        case .standard:
            KeyboardStageSurfaceStyle(
                fill: KeyboardStageRGBA(0.13, 0.14, 0.17),
                accent: KeyboardStageRGBA(0.48, 0.58, 0.72),
                legend: KeyboardStageRGBA(0.88, 0.93, 1),
                borderStrength: 0.18
            )
        case .modifier:
            KeyboardStageSurfaceStyle(
                fill: KeyboardStageRGBA(0.20, 0.24, 0.31),
                accent: KeyboardStageRGBA(0.46, 0.57, 0.74),
                legend: KeyboardStageRGBA(0.91, 0.94, 1),
                borderStrength: 0.3
            )
        case .recommended:
            KeyboardStageSurfaceStyle(
                fill: KeyboardStageRGBA(0.15, 0.31, 0.54),
                accent: KeyboardStageRGBA(0.34, 0.66, 1),
                legend: KeyboardStageRGBA(0.94, 0.98, 1),
                borderStrength: 0.52
            )
        case .escape:
            KeyboardStageSurfaceStyle(
                fill: KeyboardStageRGBA(0.12, 0.37, 0.66),
                accent: KeyboardStageRGBA(0.39, 0.76, 1),
                legend: KeyboardStageRGBA(0.96, 0.99, 1),
                borderStrength: 0.58
            )
        case .hyper:
            KeyboardStageSurfaceStyle(
                fill: KeyboardStageRGBA(0.35, 0.23, 0.61),
                accent: KeyboardStageRGBA(0.70, 0.55, 1),
                legend: KeyboardStageRGBA(0.98, 0.97, 1),
                borderStrength: 0.62
            )
        case .launcher:
            KeyboardStageSurfaceStyle(
                fill: KeyboardStageRGBA(0.12, 0.43, 0.45),
                accent: KeyboardStageRGBA(0.32, 0.83, 0.79),
                legend: KeyboardStageRGBA(0.94, 1, 0.99),
                borderStrength: 0.58
            )
        case .installed:
            KeyboardStageSurfaceStyle(
                fill: KeyboardStageRGBA(0.15, 0.39, 0.30),
                accent: KeyboardStageRGBA(0.38, 0.81, 0.59),
                legend: KeyboardStageRGBA(0.95, 1, 0.97),
                borderStrength: 0.5
            )
        case .dimmed:
            KeyboardStageSurfaceStyle(
                fill: KeyboardStageRGBA(0.115, 0.12, 0.14),
                accent: KeyboardStageRGBA(0.35, 0.40, 0.48),
                legend: KeyboardStageRGBA(0.66, 0.69, 0.75),
                borderStrength: 0.1
            )
        }
    }
}
