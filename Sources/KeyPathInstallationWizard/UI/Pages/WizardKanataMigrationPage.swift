import KeyPathWizardCore
import SwiftUI

/// Kanata migration page - stub for compilation
/// TODO: Move full implementation from KeyPathAppKit
public struct WizardKanataMigrationPage: View {
    public let onMigrationComplete: (Bool) -> Void
    public let onSkip: () -> Void

    public init(onMigrationComplete: @escaping (Bool) -> Void, onSkip: @escaping () -> Void) {
        self.onMigrationComplete = onMigrationComplete
        self.onSkip = onSkip
    }

    public var body: some View {
        VStack(spacing: WizardDesign.Spacing.sectionGap) {
            WizardHeroSection.info(
                icon: "arrow.triangle.2.circlepath",
                title: "Migrate Existing Kanata Config",
                subtitle: "Migration page not yet available in this module"
            )

            Button("Skip") {
                onSkip()
            }
            .buttonStyle(WizardDesign.Component.PrimaryButton())
            .keyboardShortcut(.defaultAction)
        }
        .heroSectionContainer()
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .background(WizardDesign.Colors.wizardBackground)
        .wizardDetailPage()
    }
}
