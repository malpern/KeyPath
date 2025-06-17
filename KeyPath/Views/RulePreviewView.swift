import SwiftUI

struct RulePreviewView: View {
    let rule: KanataRule
    let onConfirm: (Bool) -> Void
    
    @State private var showConfidenceWarning = false
    @State private var appearAnimation = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Text("Review Remapping Rule")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Cancel") {
                    onConfirm(false)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.top)
            
            // Visual Preview
            EnhancedRemapVisualizer(behavior: rule.visualization.behavior)
                .padding()
                .scaleEffect(appearAnimation ? 1.0 : 0.8)
                .opacity(appearAnimation ? 1.0 : 0.0)
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: appearAnimation)
            
            // Rule Details
            VStack(alignment: .leading, spacing: 16) {
                // Explanation
                VStack(alignment: .leading, spacing: 4) {
                    Text("What this does:")
                        .font(.headline)
                    Text(rule.explanation)
                        .foregroundColor(.secondary)
                }
                
                // Kanata Rule
                VStack(alignment: .leading, spacing: 4) {
                    Text("Kanata Configuration:")
                        .font(.headline)
                    Text(rule.kanataRule)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(colorScheme == .dark ? 
                                      Color.white.opacity(0.1) : 
                                      Color.black.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(colorScheme == .dark ?
                                       Color.white.opacity(0.2) :
                                       Color.black.opacity(0.1), lineWidth: 1)
                        )
                        .textSelection(.enabled)
                }
                
                // Confidence Indicator
                if rule.confidence != .high {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text("Confidence: \(rule.confidence.rawValue)")
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("What does this mean?") {
                            showConfidenceWarning = true
                        }
                        .buttonStyle(.link)
                    }
                    .padding()
                    .background(Color.yellow.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal)
            
            Spacer()
            
            // Action Buttons
            HStack(spacing: 16) {
                Button("Cancel") {
                    onConfirm(false)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                
                Button("Install Rule") {
                    onConfirm(true)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
            .padding()
        }
        .frame(width: 500, height: 600)
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
        .alert("About Confidence", isPresented: $showConfidenceWarning) {
            Button("OK") {}
        } message: {
            Text("This remapping has \(rule.confidence.rawValue) confidence. This means the AI is less certain about the exact mapping. Please review carefully before installing.")
        }
    }
}
