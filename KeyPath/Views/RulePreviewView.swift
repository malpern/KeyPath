import SwiftUI

struct RulePreviewView: View {
    let rule: KanataRule
    let onConfirm: (Bool) -> Void
    
    @State private var appearAnimation = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 32) {
            // Visual Preview
            EnhancedRemapVisualizer(behavior: rule.visualization.behavior)
                .padding()
                .scaleEffect(appearAnimation ? 1.0 : 0.8)
                .opacity(appearAnimation ? 1.0 : 0.0)
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: appearAnimation)
            
            // Add Rule Button
            Button("Add Rule") {
                onConfirm(true)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.green)
        }
        .padding(40)
        .frame(width: 400, height: 300)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ?
                      Color(NSColor.windowBackgroundColor) :
                      Color.white)
        )
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                appearAnimation = true
            }
        }
    }
}
