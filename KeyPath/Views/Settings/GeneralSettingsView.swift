import SwiftUI

struct GeneralSettingsView: View {
    @State private var securityManager = SecurityManager()
    @State private var showOnboarding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("General Settings")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.horizontal)
                .padding(.top)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                // Setup and Security Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Setup & Security")
                        .font(.headline)

                    HStack {
                        Button(action: { showOnboarding = true }) {
                            HStack {
                                Image(systemName: "questionmark.circle")
                                Text("Setup Guide")
                            }
                        }
                        .buttonStyle(.borderedProminent)

                        Spacer()

                        Button(action: {
                            securityManager.forceRefresh()
                        }) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Refresh Setup")
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Divider()

                // Chat Management Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Chat Management")
                        .font(.headline)

                    Button(action: {
                        // This would need to be connected to the main view's reset function
                        // For now, it's a placeholder
                    }) {
                        HStack {
                            Image(systemName: "square.and.pencil")
                            Text("New Chat")
                        }
                    }
                    .buttonStyle(.bordered)

                    Text("Note: Use Cmd+N or menu bar to start a new chat")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(
                securityManager: securityManager,
                showOnboarding: $showOnboarding
            )
        }
    }
}
