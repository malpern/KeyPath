import SwiftUI

struct WelcomeLogoView: View {
    @State private var isAnimating = false
    @State private var showTitle = false
    @State private var titleOpacity = 0.0
    @State private var keyboardScale = 0.8
    @State private var glowOpacity = 0.0
    
    var body: some View {
        HStack(spacing: 16) {
            // Animated keyboard icon with glow effect
            ZStack {
                // Glow effect
                Image(systemName: "keyboard.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blur(radius: 6)
                    .opacity(glowOpacity)
                    .scaleEffect(1.2)
                
                // Main keyboard icon
                Image(systemName: "keyboard.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .scaleEffect(keyboardScale)
                    .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .animation(.spring(response: 0.8, dampingFraction: 0.6), value: keyboardScale)
            .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: glowOpacity)
            
            // Animated title and tagline
            if showTitle {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 0) {
                        ForEach(Array("KeyPath".enumerated()), id: \.offset) { index, character in
                            Text(String(character))
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .opacity(titleOpacity)
                                .animation(
                                    .spring(response: 0.5, dampingFraction: 0.8)
                                    .delay(Double(index) * 0.05),
                                    value: titleOpacity
                                )
                        }
                    }
                    
                    Text("Keyboard Remapping Made Simple")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .opacity(titleOpacity * 0.8)
                        .animation(.easeInOut(duration: 0.8).delay(0.6), value: titleOpacity)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .onAppear {
            // Start animations sequence
            withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
                keyboardScale = 1.0
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation {
                    glowOpacity = 0.6
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                showTitle = true
                withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) {
                    titleOpacity = 1.0
                }
            }
        }
    }
}

struct PulsingKeyboardView: View {
    @State private var isPulsing = false
    
    var body: some View {
        ZStack {
            // Background glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.blue.opacity(0.3), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 50
                    )
                )
                .frame(width: 100, height: 100)
                .scaleEffect(isPulsing ? 1.2 : 0.8)
                .opacity(isPulsing ? 0.3 : 0.7)
            
            // Keyboard icon
            Image(systemName: "keyboard.fill")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .scaleEffect(isPulsing ? 1.1 : 0.9)
                .shadow(color: .blue.opacity(0.4), radius: 8, x: 0, y: 4)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

// Alternative minimal animated logo for smaller spaces
struct CompactLogoView: View {
    @State private var rotation = 0.0
    @State private var scale = 1.0
    
    var body: some View {
        Image(systemName: "keyboard.fill")
            .font(.system(size: 24, weight: .medium))
            .foregroundStyle(
                LinearGradient(
                    colors: [.blue, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .scaleEffect(scale)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    scale = 1.1
                }
                withAnimation(.linear(duration: 0.5).delay(0.3)) {
                    rotation = 5
                }
                withAnimation(.linear(duration: 0.5).delay(0.8)) {
                    rotation = -5
                }
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(1.3)) {
                    rotation = 0
                    scale = 1.0
                }
            }
    }
}

#Preview {
    VStack(spacing: 40) {
        WelcomeLogoView()
        
        Divider()
        
        PulsingKeyboardView()
        
        Divider()
        
        CompactLogoView()
    }
    .padding()
    .frame(width: 400, height: 600)
}