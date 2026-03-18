import SwiftUI

struct LiquidGlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .padding(14)
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
        } else {
            content
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

extension View {
    func tracerGlassCard() -> some View {
        modifier(LiquidGlassCardModifier())
    }

    @ViewBuilder
    func tracerGlassButtonStyle() -> some View {
        if #available(macOS 26, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}
