import KeyPathCore
import KeyPathWizardCore
import SwiftUI

/// Wizard page for migrating existing Kanata configurations to KeyPath
/// Shown when existing Kanata configs are detected in common locations
struct WizardKanataMigrationPage: View {
    @State private var detectedConfigs: [(path: String, displayName: String)] = []
    @State private var selectedConfigPath: String?
    @State private var migrationMethod: KanataConfigMigrationService.MigrationMethod = .copy
    @State private var prependInclude: Bool = true
    @State private var isMigrating: Bool = false
    @State private var migrationStatus: MigrationStatus = .idle
    @State private var backupPath: String?

    let onComplete: () -> Void
    let onSkip: () -> Void

    enum MigrationStatus {
        case idle
        case migrating
        case success(String?) // backup path
        case error(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Hero section
            WizardHeroSection(
                icon: "arrow.triangle.2.circlepath",
                iconColor: .blue,
                title: "Migrate Existing Kanata Config",
                subtitle: detectedConfigs.isEmpty
                    ? "No existing Kanata configs detected"
                    : "Found \(detectedConfigs.count) existing Kanata configuration\(detectedConfigs.count == 1 ? "" : "s")"
            )

            if detectedConfigs.isEmpty {
                // No configs found - show skip option
                VStack(spacing: WizardDesign.Spacing.sectionGap) {
                    Text("No existing Kanata configurations were found in common locations.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, WizardDesign.Spacing.pageVertical)
                        .padding(.top, WizardDesign.Spacing.sectionGap)

                    Button("Continue Setup") {
                        onSkip()
                    }
                    .buttonStyle(WizardDesign.Component.PrimaryButton())
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("kanata-migration-skip-button")
                }
                .heroSectionContainer()
            } else {
                // Configs found - show migration options
                ScrollView {
                    VStack(spacing: WizardDesign.Spacing.sectionGap) {
                        // Info card
                        VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
                            Text("KeyPath can use your existing Kanata configuration. Choose an option below:")
                                .font(.body)
                                .foregroundColor(.primary)

                            Text("KeyPath will preserve your configuration and add support for app-specific keymaps.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(WizardDesign.Spacing.cardPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, WizardDesign.Spacing.pageVertical)
                        .padding(.top, WizardDesign.Spacing.pageVertical)

                        // Config selection
                        VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
                            Text("Select Configuration File")
                                .font(.headline)
                                .fontWeight(.semibold)

                            ForEach(Array(detectedConfigs.enumerated()), id: \.offset) { index, config in
                                Button {
                                    selectedConfigPath = config.path
                                } label: {
                                    HStack {
                                        Image(systemName: selectedConfigPath == config.path ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(selectedConfigPath == config.path ? .accentColor : .secondary)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(config.displayName)
                                                .font(.body)
                                                .foregroundColor(.primary)
                                            Text(config.path)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(WizardDesign.Spacing.cardPadding)
                                    .background(
                                        selectedConfigPath == config.path
                                            ? Color.accentColor.opacity(0.1)
                                            : Color(NSColor.controlBackgroundColor),
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("kanata-migration-config-\(index)")
                            }
                        }
                        .padding(.horizontal, WizardDesign.Spacing.pageVertical)

                        // Migration method selection
                        if selectedConfigPath != nil {
                            VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
                                Text("Migration Method")
                                    .font(.headline)
                                    .fontWeight(.semibold)

                                Picker("Method", selection: $migrationMethod) {
                                    Text("Copy").tag(KanataConfigMigrationService.MigrationMethod.copy)
                                    Text("Symlink (for dotfiles)").tag(KanataConfigMigrationService.MigrationMethod.symlink)
                                }
                                .pickerStyle(.segmented)
                                .accessibilityIdentifier("kanata-migration-method-picker")

                                Text(migrationMethod == .copy
                                    ? "Creates a copy of your config in KeyPath's directory. Safe and recommended."
                                    : "Creates a symlink to your existing config. Use if you manage configs in a dotfiles repo.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 4)
                            }
                            .padding(.horizontal, WizardDesign.Spacing.pageVertical)

                            // Include line option (only for copy method)
                            if migrationMethod == .copy {
                                Toggle(isOn: $prependInclude) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Add KeyPath include line")
                                            .font(.body)
                                        Text("Prepends `(include keypath-apps.kbd)` to enable app-specific keymaps")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .toggleStyle(.switch)
                                .padding(.horizontal, WizardDesign.Spacing.pageVertical)
                                .accessibilityIdentifier("kanata-migration-prepend-include-toggle")
                            }
                        }

                        // Status message
                        if case let .success(backup) = migrationStatus {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Migration completed successfully")
                                        .font(.body)
                                        .fontWeight(.semibold)
                                    if let backup {
                                        Text("Backup created: \(WizardSystemPaths.displayPath(for: backup))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(WizardDesign.Spacing.cardPadding)
                            .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                            .padding(.horizontal, WizardDesign.Spacing.pageVertical)
                        } else if case let .error(message) = migrationStatus {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text(message)
                                    .font(.body)
                                Spacer()
                            }
                            .padding(WizardDesign.Spacing.cardPadding)
                            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                            .padding(.horizontal, WizardDesign.Spacing.pageVertical)
                        }

                        // Action buttons
                        HStack(spacing: WizardDesign.Spacing.elementGap) {
                            Button("Skip") {
                                onSkip()
                            }
                            .buttonStyle(WizardDesign.Component.SecondaryButton())
                            .accessibilityIdentifier("kanata-migration-skip-button")

                            if selectedConfigPath != nil {
                                Button(isMigrating ? "Migrating..." : "Migrate Config") {
                                    performMigration()
                                }
                                .buttonStyle(WizardDesign.Component.PrimaryButton())
                                .disabled(isMigrating || selectedConfigPath == nil)
                                .keyboardShortcut(.defaultAction)
                                .accessibilityIdentifier("kanata-migration-migrate-button")
                            }

                            if case .success = migrationStatus {
                                Button("Continue Setup") {
                                    onComplete()
                                }
                                .buttonStyle(WizardDesign.Component.PrimaryButton())
                                .keyboardShortcut(.defaultAction)
                                .accessibilityIdentifier("kanata-migration-continue-button")
                            }
                        }
                        .padding(.horizontal, WizardDesign.Spacing.pageVertical)
                        .padding(.top, WizardDesign.Spacing.sectionGap)
                        .padding(.bottom, WizardDesign.Spacing.pageVertical)
                    }
                }
            }
        }
        .onAppear {
            detectConfigs()
        }
    }

    private func detectConfigs() {
        detectedConfigs = WizardSystemPaths.detectExistingKanataConfigs()
        if detectedConfigs.count == 1 {
            selectedConfigPath = detectedConfigs.first?.path
        }
    }

    private func performMigration() {
        guard let sourcePath = selectedConfigPath else { return }

        isMigrating = true
        migrationStatus = .migrating

        Task {
            do {
                let migrationService = KanataConfigMigrationService()
                let backup = try migrationService.migrateConfig(
                    from: sourcePath,
                    method: migrationMethod,
                    prependInclude: prependInclude && migrationMethod == .copy
                )

                await MainActor.run {
                    migrationStatus = .success(backup)
                    backupPath = backup
                    isMigrating = false
                }
            } catch {
                await MainActor.run {
                    migrationStatus = .error(error.localizedDescription)
                    isMigrating = false
                }
            }
        }
    }
}
