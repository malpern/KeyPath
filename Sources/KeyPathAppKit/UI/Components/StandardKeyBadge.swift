import SwiftUI

struct StandardKeyBadge: View {
    let key: String
    var color: Color = .blue
    var uppercase: Bool = true

    var body: some View {
        Text(uppercase ? key.uppercased() : key)
            .font(.system(size: 14, weight: .semibold, design: .monospaced))
            .foregroundColor(color)
            .frame(minWidth: 26, minHeight: 26)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(color.opacity(0.1))
            )
    }
}
