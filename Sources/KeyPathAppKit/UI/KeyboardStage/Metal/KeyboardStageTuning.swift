import Foundation

/// Runtime-tunable lighting constants for the Metal keyboard stage.
///
/// The cinematic entrance is tuned by feel, and every constant lived as a
/// literal inside the fragment shader — each adjustment cost a build, deploy,
/// and replay. This harness moves the by-feel constants into a uniform block
/// with these values as the shipped defaults.
///
/// Developer workflow (dev builds only, zero cost when unset):
///
///     export KEYPATH_STAGE_TUNING_FILE=~/stage-tuning.json
///     /Applications/KeyPath.app/Contents/MacOS/KeyPath
///
/// Then edit the JSON while the tour is open; the stage watches the file and
/// redraws on every save. Any key omitted from the JSON keeps its default, so
/// a file containing only `{"grazeAmplitudeDeck": 0.3}` is valid. Shipped
/// behavior is unchanged: without the environment variable the defaults below
/// are uploaded and no file monitoring is installed.
struct KeyboardStageTuning: Equatable, Sendable {
    /// Warm right-side graze: deck ambient and diffuse amplitudes.
    var grazeAmplitudeDeck: Float = 0.19
    var grazeDiffuseDeck: Float = 0.115
    /// Warm right-side graze: keycap ambient and diffuse amplitudes.
    var grazeAmplitudeKey: Float = 0.040
    var grazeDiffuseKey: Float = 0.066
    /// Window-space coordinate where the warm graze begins.
    var grazeMaskStart: Float = 0.44
    /// Peak gain applied to light-facing rims during the dark hold.
    var rimDirectionalityPeak: Float = 2.2
    /// Exponent shaping how tightly rim catches hug the light-facing edge.
    var rimDirectionalityPower: Float = 1.7
    /// Minimum rim response kept on emphasized (lesson) keys off-light-side.
    var emphasisRimFloor: Float = 0.30
    /// Extra well half-width (pixels) around keycaps during the dark hold.
    var wellExpansionDark: Float = 5.6
    /// Contact and cast shadow strength multipliers during the dark hold.
    var contactShadowStrengthDark: Float = 1.62
    var castShadowStrengthDark: Float = 1.30
    /// Backlight diffuser strength during the dark hold.
    var backlightStrengthDark: Float = 0.10
    /// Legend emission range across the light axis (far side, light side).
    var legendEmissionMin: Float = 0.74
    var legendEmissionMax: Float = 1.16
    /// Legend base-brightness range across the light axis in the dark hold.
    var legendBaseMin: Float = 0.84
    var legendBaseMax: Float = 1.05
    /// Cool fill light from the lower left: overall and specular strength.
    var fillLightStrength: Float = 0.95
    var fillSpecularStrength: Float = 0.15
    /// Per-key wear (polished crowns, calmer grain on high-traffic caps).
    /// A plain multiplier: values above 1 amplify the per-key wear levels.
    var wearStrength: Float = 1.0
    /// Per-key highlight jitter (each cap catches the light slightly apart).
    var highlightJitter: Float = 2.2
    /// Window-space corner falloff; relaxes to 30% at the settled light.
    var vignetteStrength: Float = 0.58
    var vignetteInnerRadius: Float = 0.33

    static let `default` = KeyboardStageTuning()

    static let environmentVariable = "KEYPATH_STAGE_TUNING_FILE"

    var gpuVectorA: SIMD4<Float> {
        SIMD4(grazeAmplitudeDeck, grazeDiffuseDeck, grazeAmplitudeKey, grazeDiffuseKey)
    }

    var gpuVectorB: SIMD4<Float> {
        SIMD4(grazeMaskStart, rimDirectionalityPeak, rimDirectionalityPower, emphasisRimFloor)
    }

    var gpuVectorC: SIMD4<Float> {
        SIMD4(
            wellExpansionDark,
            contactShadowStrengthDark,
            castShadowStrengthDark,
            backlightStrengthDark
        )
    }

    var gpuVectorD: SIMD4<Float> {
        SIMD4(legendEmissionMin, legendEmissionMax, legendBaseMin, legendBaseMax)
    }

    var gpuVectorE: SIMD4<Float> {
        SIMD4(fillLightStrength, fillSpecularStrength, wearStrength, highlightJitter)
    }

    /// Packed into the post-pass uniforms; the renderer appends the stage's
    /// window mapping to the remaining two lanes.
    var vignetteVector: SIMD2<Float> {
        SIMD2(vignetteStrength, vignetteInnerRadius)
    }
}

extension KeyboardStageTuning: Codable {
    private enum CodingKeys: String, CodingKey {
        case grazeAmplitudeDeck
        case grazeDiffuseDeck
        case grazeAmplitudeKey
        case grazeDiffuseKey
        case grazeMaskStart
        case rimDirectionalityPeak
        case rimDirectionalityPower
        case emphasisRimFloor
        case wellExpansionDark
        case contactShadowStrengthDark
        case castShadowStrengthDark
        case backlightStrengthDark
        case legendEmissionMin
        case legendEmissionMax
        case legendBaseMin
        case legendBaseMax
        case fillLightStrength
        case fillSpecularStrength
        case wearStrength
        case highlightJitter
        case vignetteStrength
        case vignetteInnerRadius
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.default

        func value(_ key: CodingKeys, _ fallback: Float) -> Float {
            (try? container.decodeIfPresent(Float.self, forKey: key)) ?? nil ?? fallback
        }

        grazeAmplitudeDeck = value(.grazeAmplitudeDeck, defaults.grazeAmplitudeDeck)
        grazeDiffuseDeck = value(.grazeDiffuseDeck, defaults.grazeDiffuseDeck)
        grazeAmplitudeKey = value(.grazeAmplitudeKey, defaults.grazeAmplitudeKey)
        grazeDiffuseKey = value(.grazeDiffuseKey, defaults.grazeDiffuseKey)
        grazeMaskStart = value(.grazeMaskStart, defaults.grazeMaskStart)
        rimDirectionalityPeak = value(.rimDirectionalityPeak, defaults.rimDirectionalityPeak)
        rimDirectionalityPower = value(.rimDirectionalityPower, defaults.rimDirectionalityPower)
        emphasisRimFloor = value(.emphasisRimFloor, defaults.emphasisRimFloor)
        wellExpansionDark = value(.wellExpansionDark, defaults.wellExpansionDark)
        contactShadowStrengthDark = value(
            .contactShadowStrengthDark,
            defaults.contactShadowStrengthDark
        )
        castShadowStrengthDark = value(.castShadowStrengthDark, defaults.castShadowStrengthDark)
        backlightStrengthDark = value(.backlightStrengthDark, defaults.backlightStrengthDark)
        legendEmissionMin = value(.legendEmissionMin, defaults.legendEmissionMin)
        legendEmissionMax = value(.legendEmissionMax, defaults.legendEmissionMax)
        legendBaseMin = value(.legendBaseMin, defaults.legendBaseMin)
        legendBaseMax = value(.legendBaseMax, defaults.legendBaseMax)
        fillLightStrength = value(.fillLightStrength, defaults.fillLightStrength)
        fillSpecularStrength = value(.fillSpecularStrength, defaults.fillSpecularStrength)
        wearStrength = value(.wearStrength, defaults.wearStrength)
        highlightJitter = value(.highlightJitter, defaults.highlightJitter)
        vignetteStrength = value(.vignetteStrength, defaults.vignetteStrength)
        vignetteInnerRadius = value(.vignetteInnerRadius, defaults.vignetteInnerRadius)
    }

    /// Loads overrides from a JSON file; unknown keys are ignored and missing
    /// keys keep their shipped defaults.
    static func load(from url: URL) throws -> KeyboardStageTuning {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(KeyboardStageTuning.self, from: data)
    }

    /// The tuning-file URL from the environment, when the harness is active.
    static var environmentFileURL: URL? {
        guard let path = ProcessInfo.processInfo.environment[environmentVariable],
              !path.isEmpty
        else {
            return nil
        }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }
}
