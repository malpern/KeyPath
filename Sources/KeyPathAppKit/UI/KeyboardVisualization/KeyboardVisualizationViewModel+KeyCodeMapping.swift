extension KeyboardVisualizationViewModel {
    /// Maps Kanata key names, such as "h", "j", and "space", to macOS key codes.
    nonisolated static func kanataNameToKeyCode(_ name: String) -> UInt16? {
        KanataKeyCodeMap.keyCode(for: name)
    }
}
