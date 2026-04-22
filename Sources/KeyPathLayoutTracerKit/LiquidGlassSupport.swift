import SwiftUI

struct LiquidGlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        // See note on LayoutTracerCanvasView.canvasBackground — need a
        // compile-time gate, not just a runtime #available check.
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            content
                .padding(14)
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
        } else {
            content
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        #else
        content
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        #endif
    }
}

extension View {
    func tracerGlassCard() -> some View {
        modifier(LiquidGlassCardModifier())
    }

    @ViewBuilder
    func tracerGlassButtonStyle() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
        #else
        self.buttonStyle(.bordered)
        #endif
    }
}
