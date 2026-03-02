import KeyPathCore
import KeyPathWizardCore
import SwiftUI

/// Wizard page for importing Karabiner-Elements rules during installation.
/// Shown when a Karabiner config is detected and conflicts have been resolved.
struct WizardKarabinerImportPage: View {
    @Environment(KanataViewModel.self) var kanataManager

    @State private var conversionResult: KarabinerConversionResult?
    @State private var isConverting = false
    @State private var errorMessage: String?
    @State private var selectedCollectionIds: Set<UUID> = []
    @State private var selectedAppKeymapIds: Set<UUID> = []
    @State private var importComplete = false

    // Animation states
    @State private var heroScale: CGFloat = 0.8
    @State private var heroOpacity: Double = 0

    let onImportComplete: () -> Void
    let onSkip: () -> Void

    private let converterService = KarabinerConverterService()

    var body: some View {
        VStack(spacing: 0) {
            WizardHeroSection(
                icon: "square.and.arrow.down",
                iconColor: .purple,
                title: "Import Karabiner Rules",
                subtitle: "Bring your existing rules into KeyPath"
            )
            .scaleEffect(heroScale)
            .opacity(heroOpacity)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if importComplete {
                        importCompleteView
                    } else if let result = conversionResult {
                        resultsView(result)
                    } else if isConverting {
                        convertingView
                    } else {
                        detectionView
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
            }

            Spacer()

            // Action buttons
            HStack(spacing: 12) {
                Button("Skip") { onSkip() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("wizard-karabiner-skip")

                Spacer()

                if importComplete {
                    Button("Continue") { onImportComplete() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("wizard-karabiner-continue")
                } else if conversionResult != nil {
                    let count = selectedCollectionIds.count + selectedAppKeymapIds.count
                    Button("Import \(count) Rule\(count == 1 ? "" : "s")") {
                        Task { await performImport() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(count == 0)
                    .accessibilityIdentifier("wizard-karabiner-import")
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                heroScale = 1.0
                heroOpacity = 1.0
            }
            Task { await autoConvert() }
        }
    }

    // MARK: - Sub-Views

    private var detectionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading) {
                    Text("Karabiner configuration found")
                        .fontWeight(.medium)
                    Text(WizardSystemPaths.karabinerConfigPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.1))
            .clipShape(.rect(cornerRadius: 8))

            Text("KeyPath can import your existing Karabiner rules as editable KeyPath rule collections.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var convertingView: some View {
        HStack {
            ProgressView()
            Text("Analyzing Karabiner configuration...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 40)
    }

    private func resultsView(_ result: KarabinerConversionResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Summary
            let converted = result.collections.count + result.appKeymaps.count
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("\(converted) rule\(converted == 1 ? "" : "s") ready to import")
                    .fontWeight(.medium)
                if !result.skippedRules.isEmpty {
                    Text("(\(result.skippedRules.count) skipped)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Collections
            if !result.collections.isEmpty {
                Text("Rule Collections")
                    .font(.headline)
                ForEach(result.collections) { collection in
                    wizardCheckboxRow(
                        title: collection.name,
                        subtitle: "\(collection.mappings.count) mapping\(collection.mappings.count == 1 ? "" : "s")",
                        isSelected: selectedCollectionIds.contains(collection.id)
                    ) {
                        if selectedCollectionIds.contains(collection.id) {
                            selectedCollectionIds.remove(collection.id)
                        } else {
                            selectedCollectionIds.insert(collection.id)
                        }
                    }
                }
            }

            // App keymaps
            if !result.appKeymaps.isEmpty {
                Text("App-Specific Rules")
                    .font(.headline)
                ForEach(result.appKeymaps) { keymap in
                    wizardCheckboxRow(
                        title: keymap.mapping.displayName,
                        subtitle: "\(keymap.overrides.count) override\(keymap.overrides.count == 1 ? "" : "s")",
                        isSelected: selectedAppKeymapIds.contains(keymap.id)
                    ) {
                        if selectedAppKeymapIds.contains(keymap.id) {
                            selectedAppKeymapIds.remove(keymap.id)
                        } else {
                            selectedAppKeymapIds.insert(keymap.id)
                        }
                    }
                }
            }
        }
    }

    private var importCompleteView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Rules imported successfully!")
                .font(.headline)
            Text("Your Karabiner rules are now available in KeyPath.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func wizardCheckboxRow(
        title: String,
        subtitle: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }

    // MARK: - Actions

    private func autoConvert() async {
        guard WizardSystemPaths.karabinerConfigExists else { return }
        isConverting = true

        let path = WizardSystemPaths.karabinerConfigPath
        guard let data = FileManager.default.contents(atPath: path) else {
            errorMessage = "Could not read Karabiner config file"
            isConverting = false
            return
        }

        do {
            let result = try await converterService.convert(data: data, profileIndex: nil)
            conversionResult = result
            selectedCollectionIds = Set(result.collections.map(\.id))
            selectedAppKeymapIds = Set(result.appKeymaps.map(\.id))
        } catch {
            errorMessage = error.localizedDescription
        }

        isConverting = false
    }

    private func performImport() async {
        guard let result = conversionResult else { return }

        for collection in result.collections where selectedCollectionIds.contains(collection.id) {
            await kanataManager.addRuleCollection(collection)
        }

        for keymap in result.appKeymaps where selectedAppKeymapIds.contains(keymap.id) {
            try? await AppKeymapStore.shared.upsertKeymap(keymap)
        }

        // Also persist any launcher mappings from the conversion
        if !result.launcherMappings.isEmpty {
            await persistLauncherMappings(result.launcherMappings)
        }

        withAnimation {
            importComplete = true
        }
    }

    private func persistLauncherMappings(_ newMappings: [LauncherMapping]) async {
        var collections = await RuleCollectionStore.shared.loadCollections()
        guard let index = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.launcher }) else { return }
        var collection = collections[index]
        guard var config = collection.configuration.launcherGridConfig else { return }

        config.mappings.append(contentsOf: newMappings)
        collection.configuration = .launcherGrid(config)
        collections[index] = collection
        try? await RuleCollectionStore.shared.saveCollections(collections)
        NotificationCenter.default.post(name: .ruleCollectionsChanged, object: nil)
    }
}
