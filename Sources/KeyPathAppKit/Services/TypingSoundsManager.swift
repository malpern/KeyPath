import AppKit
import AVFoundation
import KeyPathCore

// MARK: - Sound Profile Model

/// A typing sound profile representing a mechanical keyboard switch type
struct SoundProfile: Identifiable, Equatable {
    let id: String
    let name: String
    let shortName: String
    let descriptor: String
    let color: NSColor
    let icon: String // SF Symbol or emoji

    static let off = SoundProfile(
        id: "off",
        name: "Off",
        shortName: "Off",
        descriptor: "Silent typing",
        color: .systemGray,
        icon: "speaker.slash"
    )

    static let mxBlue = SoundProfile(
        id: "mx-blue",
        name: "Cherry MX Blue",
        shortName: "Blue",
        descriptor: "Clicky, loud",
        color: .systemBlue,
        icon: "circle.fill"
    )

    static let mxBrown = SoundProfile(
        id: "mx-brown",
        name: "Cherry MX Brown",
        shortName: "Brown",
        descriptor: "Tactile bump",
        color: .brown,
        icon: "circle.fill"
    )

    static let mxRed = SoundProfile(
        id: "mx-red",
        name: "Cherry MX Red",
        shortName: "Red",
        descriptor: "Smooth linear",
        color: .systemRed,
        icon: "circle.fill"
    )

    static let nkCream = SoundProfile(
        id: "nk-cream",
        name: "NK Cream",
        shortName: "Cream",
        descriptor: "Deep, thocky",
        color: NSColor(red: 0.96, green: 0.94, blue: 0.88, alpha: 1.0),
        icon: "circle.fill"
    )

    static let bubblePop = SoundProfile(
        id: "bubble-pop",
        name: "Bubble Pop",
        shortName: "Pop",
        descriptor: "Playful, silly",
        color: .systemPink,
        icon: "bubble.left.fill"
    )

    /// All available profiles
    static let all: [SoundProfile] = [.off, .mxBlue, .mxBrown, .mxRed, .nkCream, .bubblePop]
}

// MARK: - Typing Sounds Manager

/// Manages keyboard typing sound playback
@MainActor
final class TypingSoundsManager: ObservableObject {
    static let shared = TypingSoundsManager()

    /// Currently selected sound profile
    @Published var selectedProfile: SoundProfile = .off {
        didSet {
            UserDefaults.standard.set(selectedProfile.id, forKey: "typingSoundProfileId")
            if selectedProfile.id != SoundProfile.off.id {
                preloadSounds(for: selectedProfile)
            }
        }
    }

    /// Volume level (0.0 to 1.0)
    @Published var volume: Float = 0.7 {
        didSet {
            UserDefaults.standard.set(volume, forKey: "typingSoundVolume")
        }
    }

    /// Whether the Typing Sounds collection is enabled
    @Published var isCollectionEnabled: Bool = false

    /// Whether sounds are enabled (collection must be enabled and profile not "off")
    var isEnabled: Bool {
        isCollectionEnabled && selectedProfile.id != SoundProfile.off.id
    }

    /// Load the collection enabled state from RuleCollectionStore
    func loadCollectionState() {
        Task { @MainActor in
            let collections = await RuleCollectionStore.shared.loadCollections()
            isCollectionEnabled = collections.first { $0.id == RuleCollectionIdentifier.typingSounds }?.isEnabled ?? false
        }
    }

    /// Audio players for keydown sounds
    private var keydownPlayers: [AVAudioPlayer] = []
    /// Audio players for keyup sounds
    private var keyupPlayers: [AVAudioPlayer] = []
    /// Index for round-robin player selection
    private var keydownIndex = 0
    private var keyupIndex = 0
    /// Number of concurrent players per sound type
    private let playerPoolSize = 8

    /// Observer for rule collection changes
    private var ruleCollectionsObserver: Any?

    private init() {
        // Restore saved preferences
        if let savedProfileId = UserDefaults.standard.string(forKey: "typingSoundProfileId"),
           let profile = SoundProfile.all.first(where: { $0.id == savedProfileId })
        {
            selectedProfile = profile
            if profile.id != SoundProfile.off.id {
                preloadSounds(for: profile)
            }
        }
        volume = UserDefaults.standard.object(forKey: "typingSoundVolume") as? Float ?? 0.7
        loadCollectionState()
        setupRuleCollectionsObserver()
    }

    /// Set up observer for rule collections changed notification (for real-time enable/disable)
    private func setupRuleCollectionsObserver() {
        ruleCollectionsObserver = NotificationCenter.default.addObserver(
            forName: .ruleCollectionsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.loadCollectionState()
                AppLogger.shared.debug("🔊 [TypingSounds] Reloaded collection state after change")
            }
        }
    }

    // MARK: - Sound Playback

    /// Play keydown sound
    func playKeydown() {
        guard isEnabled, !keydownPlayers.isEmpty else { return }

        let player = keydownPlayers[keydownIndex]
        keydownIndex = (keydownIndex + 1) % keydownPlayers.count

        player.volume = volume
        player.currentTime = 0
        player.play()
    }

    /// Play keyup sound
    func playKeyup() {
        guard isEnabled, !keyupPlayers.isEmpty else { return }

        let player = keyupPlayers[keyupIndex]
        keyupIndex = (keyupIndex + 1) % keyupPlayers.count

        player.volume = volume * 0.7 // Keyup slightly quieter
        player.currentTime = 0
        player.play()
    }

    /// Play a sample of the given profile (for preview on hover)
    func playSample(for profile: SoundProfile) {
        guard profile.id != SoundProfile.off.id else { return }

        // Load and play a quick sample
        Task {
            if let keydownURL = soundURL(for: profile, isKeydown: true),
               let player = try? AVAudioPlayer(contentsOf: keydownURL)
            {
                player.volume = volume
                player.play()

                // Play keyup after short delay
                try? await Task.sleep(for: .milliseconds(80))

                if let keyupURL = soundURL(for: profile, isKeydown: false),
                   let keyupPlayer = try? AVAudioPlayer(contentsOf: keyupURL)
                {
                    keyupPlayer.volume = volume * 0.7
                    keyupPlayer.play()
                }
            }
        }
    }

    // MARK: - Sound Loading

    private func preloadSounds(for profile: SoundProfile) {
        keydownPlayers.removeAll()
        keyupPlayers.removeAll()

        guard let keydownURL = soundURL(for: profile, isKeydown: true),
              let keyupURL = soundURL(for: profile, isKeydown: false)
        else {
            AppLogger.shared.warn("Could not find sound files for profile: \(profile.id)")
            return
        }

        // Create pool of players for each sound type
        for _ in 0 ..< playerPoolSize {
            if let player = try? AVAudioPlayer(contentsOf: keydownURL) {
                player.prepareToPlay()
                keydownPlayers.append(player)
            }
            if let player = try? AVAudioPlayer(contentsOf: keyupURL) {
                player.prepareToPlay()
                keyupPlayers.append(player)
            }
        }

        keydownIndex = 0
        keyupIndex = 0

        AppLogger.shared.debug("Preloaded \(keydownPlayers.count) keydown and \(keyupPlayers.count) keyup sounds for \(profile.name)")
    }

    private func soundURL(for profile: SoundProfile, isKeydown: Bool) -> URL? {
        let suffix = isKeydown ? "down" : "up"
        let filename = "\(profile.id)-\(suffix)"

        // Try Bundle.module first (Swift Package resources), then Bundle.main
        // Note: .process() in Package.swift flattens directory structure, so files
        // are at bundle root, not in a Sounds subdirectory
        if let url = Bundle.module.url(forResource: filename, withExtension: "mp3") {
            return url
        }
        if let url = Bundle.module.url(forResource: filename, withExtension: "wav") {
            return url
        }
        if let url = Bundle.main.url(forResource: filename, withExtension: "mp3") {
            return url
        }
        if let url = Bundle.main.url(forResource: filename, withExtension: "wav") {
            return url
        }

        return nil
    }
}
