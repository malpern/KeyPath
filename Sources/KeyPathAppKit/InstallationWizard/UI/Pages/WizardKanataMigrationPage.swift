import KeyPathCore
import KeyPathWizardCore
import SwiftUI

/// Wizard page for migrating existing Kanata configurations to KeyPath
/// Page 1 of the Kanata user migration flow
/// Shows when existing Kanata config is detected (from running process or config files)
struct WizardKanataMigrationPage: View {
    @State private var detectedConfig: DetectedConfig?
    @State private var runningKanataInfo: WizardSystemPaths.RunningKanataInfo?
    @State private var isMigrating = false
    @State private var migrationError: String?
    @State private var showFilePicker = false

    // Animation states
    @State private var showConfigCard = false
    @State private var showCheckmarks = [false, false, false]
    @State private var heroScale: CGFloat = 0.8
    @State private var heroOpacity: Double = 0

    let onMigrationComplete: (Bool) -> Void // hasRunningKanata
    let onSkip: () -> Void

    enum DetectedConfig {
        case fromRunningProcess(path: String, pid: Int)
        case fromFile(path: String)

        var path: String {
            switch self {
            case let .fromRunningProcess(path, _): path
            case let .fromFile(path): path
            }
        }

        var displayPath: String {
            WizardSystemPaths.displayPath(for: path)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Hero section with entrance animation
            WizardHeroSection(
                icon: "keyboard",
                iconColor: .blue,
                title: "Welcome, Kanata user!",
                subtitle: detectedConfig != nil
                    ? "We detected your config"
                    : "No existing Kanata config detected"
            )
            .scaleEffect(heroScale)
            .opacity(heroOpacity)

            if let config = detectedConfig {
                configDetectedView(config: config)
            } else {
                noConfigView()
            }
        }
        .onAppear {
            detectConfig()
            animateEntrance()
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.plainText],
            allowsMultipleSelection: false
        ) { result in
            handleFilePicker(result)
        }
    }

    // MARK: - Entrance Animation

    private func animateEntrance() {
        // Hero entrance
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            heroScale = 1.0
            heroOpacity = 1.0
        }

        // Config card slides in
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2)) {
            showConfigCard = true
        }

        // Staggered checkmarks
        for i in 0 ..< 3 {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.4 + Double(i) * 0.1)) {
                showCheckmarks[i] = true
            }
        }
    }

    // MARK: - Config Detected View

    @ViewBuilder
    private func configDetectedView(config: DetectedConfig) -> some View {
        ScrollView {
            VStack(spacing: WizardDesign.Spacing.sectionGap) {
                // Config path display with slide-in animation
                HStack {
                    Image(systemName: "doc.text.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text(config.displayPath)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding(WizardDesign.Spacing.cardPadding)
                .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, WizardDesign.Spacing.pageVertical)
                .padding(.top, WizardDesign.Spacing.sectionGap)
                .opacity(showConfigCard ? 1 : 0)
                .offset(x: showConfigCard ? 0 : -20)

                // Reassurance checkmarks with staggered animation
                VStack(alignment: .leading, spacing: 12) {
                    reassuranceRow(text: "Your mappings stay exactly as they are", index: 0)
                    reassuranceRow(text: "We just add one line for KeyPath features", index: 1)
                    reassuranceRow(text: "You can undo anytime", index: 2)
                }
                .padding(.horizontal, WizardDesign.Spacing.pageVertical)
                .padding(.top, WizardDesign.Spacing.elementGap)

                // Error message if any
                if let error = migrationError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.body)
                        Spacer()
                    }
                    .padding(WizardDesign.Spacing.cardPadding)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, WizardDesign.Spacing.pageVertical)
                }

                // Action buttons
                VStack(spacing: WizardDesign.Spacing.elementGap) {
                    HStack(spacing: WizardDesign.Spacing.elementGap) {
                        Button(isMigrating ? "Migrating..." : "Use This Config") {
                            performMigration(configPath: config.path)
                        }
                        .buttonStyle(WizardDesign.Component.PrimaryButton())
                        .disabled(isMigrating)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("kanata-migration-use-config-button")

                        Button("Choose Different") {
                            showFilePicker = true
                        }
                        .buttonStyle(WizardDesign.Component.SecondaryButton())
                        .disabled(isMigrating)
                        .accessibilityIdentifier("kanata-migration-choose-different-button")
                    }

                    Button("Skip for now") {
                        onSkip()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .accessibilityIdentifier("kanata-migration-skip-button")
                }
                .padding(.horizontal, WizardDesign.Spacing.pageVertical)
                .padding(.top, WizardDesign.Spacing.sectionGap)
                .padding(.bottom, WizardDesign.Spacing.pageVertical)
            }
        }
    }

    // MARK: - No Config View

    @ViewBuilder
    private func noConfigView() -> some View {
        VStack(spacing: WizardDesign.Spacing.sectionGap) {
            Text("No existing Kanata configuration was found.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, WizardDesign.Spacing.pageVertical)
                .padding(.top, WizardDesign.Spacing.sectionGap)

            VStack(spacing: WizardDesign.Spacing.elementGap) {
                Button("Choose Config File") {
                    showFilePicker = true
                }
                .buttonStyle(WizardDesign.Component.PrimaryButton())
                .accessibilityIdentifier("kanata-migration-choose-file-button")

                Button("Continue without migration") {
                    onSkip()
                }
                .buttonStyle(WizardDesign.Component.SecondaryButton())
                .accessibilityIdentifier("kanata-migration-continue-button")
            }
            .padding(.horizontal, WizardDesign.Spacing.pageVertical)
        }
        .heroSectionContainer()
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func reassuranceRow(text: String, index: Int) -> some View {
        let isVisible = index < showCheckmarks.count ? showCheckmarks[index] : true

        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.body)
                .scaleEffect(isVisible ? 1 : 0)
                .opacity(isVisible ? 1 : 0)
            Text(text)
                .font(.body)
                .foregroundColor(.primary)
                .opacity(isVisible ? 1 : 0)
                .offset(x: isVisible ? 0 : -10)
            Spacer()
        }
    }

    // MARK: - Detection

    private func detectConfig() {
        // Priority 1: Running Kanata process (get config from args)
        if let runningInfo = WizardSystemPaths.detectRunningKanataProcess(),
           !runningInfo.isKeyPathManaged {
            runningKanataInfo = runningInfo
            if let configPath = runningInfo.configPath {
                detectedConfig = .fromRunningProcess(path: configPath, pid: runningInfo.pid)
                return
            }
        }

        // Priority 2: Config files in common locations
        let foundConfigs = WizardSystemPaths.detectExistingKanataConfigs()
        if let first = foundConfigs.first {
            detectedConfig = .fromFile(path: first.path)
        }
    }

    // MARK: - Migration

    private func performMigration(configPath: String) {
        isMigrating = true
        migrationError = nil

        Task {
            do {
                let migrationService = KanataConfigMigrationService()

                // Always use symlink, always prepend include
                _ = try migrationService.migrateConfig(
                    from: configPath,
                    method: .symlink,
                    prependInclude: true
                )

                // If symlink was created, add include line to the SOURCE file
                // (symlink method doesn't modify the file, so we do it separately)
                if !migrationService.hasIncludeLine(configPath: configPath) {
                    _ = try migrationService.prependIncludeLineIfMissing(to: configPath)
                }

                await MainActor.run {
                    isMigrating = false
                    // Pass whether there's a running kanata to stop
                    let hasRunning = runningKanataInfo != nil && !(runningKanataInfo?.isKeyPathManaged ?? true)
                    onMigrationComplete(hasRunning)
                }
            } catch let error as KanataConfigMigrationService.MigrationError {
                await MainActor.run {
                    if case .includeAlreadyPresent = error {
                        // Not really an error - proceed
                        let hasRunning = runningKanataInfo != nil && !(runningKanataInfo?.isKeyPathManaged ?? true)
                        onMigrationComplete(hasRunning)
                    } else {
                        migrationError = error.localizedDescription
                        isMigrating = false
                    }
                }
            } catch {
                await MainActor.run {
                    migrationError = error.localizedDescription
                    isMigrating = false
                }
            }
        }
    }

    // MARK: - File Picker

    private func handleFilePicker(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else { return }
            // Security-scoped access
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            let path = url.path
            detectedConfig = .fromFile(path: path)

        case let .failure(error):
            migrationError = error.localizedDescription
        }
    }
}
