import SwiftUI

/// Shared state for tracking mouse interaction with the virtual keyboard overlay.
/// Used to implement refined click delay behavior:
/// - 300ms delay only on first hover after mouse enters keyboard area
/// - Instant clicks on subsequent keys (no delay between key clicks)
/// - Reset delay when mouse exits keyboard area
@MainActor
final class KeyboardMouseState: ObservableObject {
    /// Whether the user has clicked any key since entering the keyboard area
    @Published var hasClickedAnyKey: Bool = false

    /// Reset state when mouse exits keyboard area
    func reset() {
        hasClickedAnyKey = false
    }

    /// Mark that a key has been clicked
    func recordClick() {
        hasClickedAnyKey = true
    }
}
