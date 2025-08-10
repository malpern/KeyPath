import SwiftUI

// MARK: - System Settings Waiting View

struct SystemSettingsWaitingView: View {
  @Binding var detectionAttempts: Int
  let maxAttempts: Int
  let onDetected: () -> Void
  let onTimeout: () -> Void
  let onCancel: () -> Void

  private var timeRemaining: Int {
    (maxAttempts - detectionAttempts) * 2
  }

  private var progressValue: Double {
    Double(detectionAttempts) / Double(maxAttempts)
  }

  var body: some View {
    VStack(spacing: 24) {
      // Icon
      Image(systemName: "gear.badge.checkmark")
        .font(.system(size: 60))
        .foregroundColor(.blue)
        .symbolRenderingMode(.hierarchical)

      // Title
      Text("Waiting for System Settings...")
        .font(.title2)
        .fontWeight(.semibold)

      // Instructions
      VStack(spacing: 12) {
        Text("Please complete these steps:")
          .font(.headline)
          .foregroundColor(.primary)

        VStack(alignment: .leading, spacing: 8) {
          InstructionRow(number: 1, text: "Find KeyPath in the app list")
          InstructionRow(number: 2, text: "Toggle the switch to enable Full Disk Access")
          InstructionRow(number: 3, text: "You may need to enter your password")
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
      }

      // Progress indicator
      VStack(spacing: 8) {
        ProgressView(value: progressValue)
          .progressViewStyle(LinearProgressViewStyle())
          .frame(width: 300)

        if timeRemaining > 0 {
          Text("Checking for permission... \(timeRemaining)s remaining")
            .font(.caption)
            .foregroundColor(.secondary)
        } else {
          Text("Detection timeout - restart may be required")
            .font(.caption)
            .foregroundColor(.orange)
        }
      }

      // Animated checking indicator
      HStack(spacing: 8) {
        ForEach(0..<3) { index in
          Circle()
            .fill(Color.blue.opacity(0.7))
            .frame(width: 8, height: 8)
            .scaleEffect(detectionAttempts % 3 == index ? 1.3 : 1.0)
            .animation(
              .easeInOut(duration: 0.6).delay(Double(index) * 0.2), value: detectionAttempts)
        }
      }
      .padding(.top, 8)

      // Cancel button
      Button("Cancel") {
        onCancel()
      }
      .buttonStyle(WizardDesign.Component.SecondaryButton())
      .padding(.top, 12)
    }
    .padding(32)
    .frame(width: 450, height: 500)
    .background(Color(NSColor.windowBackgroundColor))
  }
}

// MARK: - Restart Required View

struct RestartRequiredView: View {
  let onRestart: () -> Void
  let onCancel: () -> Void

  @State private var isRestarting = false

  var body: some View {
    VStack(spacing: 24) {
      // Icon
      ZStack {
        Circle()
          .fill(Color.orange.opacity(0.1))
          .frame(width: 80, height: 80)

        Image(systemName: "arrow.clockwise.circle.fill")
          .font(.system(size: 50))
          .foregroundColor(.orange)
          .symbolRenderingMode(.hierarchical)
      }

      // Title
      Text("Restart Required")
        .font(.title2)
        .fontWeight(.semibold)

      // Explanation
      VStack(spacing: 12) {
        Text("Full Disk Access requires KeyPath to restart")
          .font(.headline)
          .foregroundColor(.primary)

        Text(
          "After granting Full Disk Access in System Settings, KeyPath needs to restart for the permission to take effect. The wizard will resume where you left off after restarting."
        )
        .font(.body)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.horizontal)

      // What will happen
      VStack(alignment: .leading, spacing: 8) {
        Label("Your wizard progress will be saved", systemImage: "checkmark.circle.fill")
          .foregroundColor(.green)
          .font(.subheadline)

        Label("KeyPath will quit and you'll need to reopen it", systemImage: "info.circle.fill")
          .foregroundColor(.blue)
          .font(.subheadline)

        Label("The wizard will continue from this page", systemImage: "arrow.right.circle.fill")
          .foregroundColor(.blue)
          .font(.subheadline)
      }
      .padding()
      .background(Color(NSColor.controlBackgroundColor))
      .cornerRadius(8)

      // Action buttons
      HStack(spacing: 12) {
        Button("Not Now") {
          onCancel()
        }
        .buttonStyle(WizardDesign.Component.SecondaryButton())

        Button(isRestarting ? "Restarting..." : "Restart KeyPath") {
          isRestarting = true
          // Small delay for UI feedback
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            onRestart()
          }
        }
        .buttonStyle(WizardDesign.Component.PrimaryButton(isLoading: isRestarting))
        .disabled(isRestarting)
      }
      .padding(.top, 12)

      // Alternative option
      Text("Tip: You can also manually quit and reopen KeyPath")
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.top, 8)
    }
    .padding(32)
    .frame(width: 500, height: 550)
    .background(Color(NSColor.windowBackgroundColor))
  }
}

// MARK: - Helper Components

private struct InstructionRow: View {
  let number: Int
  let text: String

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      ZStack {
        Circle()
          .fill(Color.blue.opacity(0.2))
          .frame(width: 24, height: 24)

        Text("\(number)")
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(.blue)
      }

      Text(text)
        .font(.body)
        .foregroundColor(.primary)
        .fixedSize(horizontal: false, vertical: true)

      Spacer()
    }
  }
}

// MARK: - Success Animation View

struct FDASuccessAnimationView: View {
  @State private var isAnimating = false

  var body: some View {
    VStack(spacing: 20) {
      ZStack {
        Circle()
          .fill(Color.green.opacity(0.1))
          .frame(width: 100, height: 100)
          .scaleEffect(isAnimating ? 1.2 : 1.0)

        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 60))
          .foregroundColor(.green)
          .scaleEffect(isAnimating ? 1.1 : 1.0)
      }
      .animation(.spring(response: 0.5, dampingFraction: 0.6), value: isAnimating)

      Text("Full Disk Access Granted!")
        .font(.title2)
        .fontWeight(.semibold)

      Text("Enhanced diagnostics are now available")
        .font(.body)
        .foregroundColor(.secondary)
    }
    .onAppear {
      isAnimating = true
    }
  }
}
