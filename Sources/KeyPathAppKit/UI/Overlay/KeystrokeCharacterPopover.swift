import SwiftUI

struct KeystrokeCharacterPopover: View {
    let char: TextRunCharacter
    let previousChar: TextRunCharacter?

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            row(label: "Key", value: char.rawKey)
            if let layer = char.layer {
                row(label: "Layer", value: layer)
            }
            row(label: "Time", value: Self.timeFormatter.string(from: char.timestamp))
            if let prev = previousChar {
                let intervalMs = Int(char.timestamp.timeIntervalSince(prev.timestamp) * 1000)
                row(label: "Since prev", value: "\(intervalMs)ms")
            }
        }
        .padding(8)
        .font(.system(size: 10, design: .monospaced))
    }

    private func row(label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
            Text(value)
                .foregroundStyle(.primary)
        }
    }
}
