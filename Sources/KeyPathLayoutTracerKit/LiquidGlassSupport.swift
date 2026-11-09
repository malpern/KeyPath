import SwiftUI

struct LiquidGlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}

extension View {
    func tracerGlassCard() -> some View {
        modifier(LiquidGlassCardModifier())
    }

    func tracerGlassButtonStyle() -> some View {
        buttonStyle(.glass)
    }
}
