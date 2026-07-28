import AppKit
import KeyPathRulesCore
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// The small, durable choice produced by the third first-success lesson.
///
/// The model stores canonical launcher keys even when the control displays a
/// logical-keymap label, so its mapping can be merged directly into the real
/// Quick Launcher configuration.
@MainActor
@Observable
final class FirstSuccessLauncherChoiceModel {
    var selectedApp: AppLaunchInfo?
    private(set) var canonicalKey: String
    private(set) var displayedKey: String
    private(set) var occupiedCanonicalKeys: Set<String>

    private let mappingID = UUID()

    init(
        selectedApp: AppLaunchInfo? = nil,
        canonicalKey: String = "",
        occupiedCanonicalKeys: Set<String> = []
    ) {
        self.selectedApp = selectedApp
        self.canonicalKey = ""
        displayedKey = ""
        self.occupiedCanonicalKeys = []
        setOccupiedCanonicalKeys(occupiedCanonicalKeys)
        setCanonicalKey(canonicalKey)
    }

    func setCanonicalKey(_ key: String) {
        setCanonicalKey(key, displayedAs: key)
    }

    func setCanonicalKey(_ key: String, displayedAs displayedKey: String) {
        let candidate = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        canonicalKey = Self.normalizedLauncherKey(from: candidate) ?? candidate
        self.displayedKey = displayedKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func setOccupiedCanonicalKeys(_ keys: Set<String>) {
        occupiedCanonicalKeys = Set(keys.compactMap(Self.normalizedLauncherKey(from:)))
    }

    static func replacementDisplayGrapheme(
        from displayValue: String,
        replacing existingDisplayValue: String
    ) -> String {
        var graphemes = Array(
            displayValue.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard !graphemes.isEmpty else { return "" }

        let existingGraphemes = Array(
            existingDisplayValue.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if graphemes.count > 1,
           let existingGrapheme = existingGraphemes.first,
           let existingIndex = graphemes.firstIndex(of: existingGrapheme)
        {
            graphemes.remove(at: existingIndex)
        }
        return graphemes.last.map(String.init) ?? ""
    }

    var mapping: LauncherMapping? {
        guard canApply, let selectedApp else { return nil }
        return LauncherMapping(
            id: mappingID,
            key: canonicalKey,
            action: .launchApp(
                name: selectedApp.name,
                bundleId: selectedApp.bundleIdentifier
            )
        )
    }

    var canApply: Bool {
        validationMessage == nil
    }

    var validationMessage: LocalizedStringResource? {
        if selectedApp == nil, canonicalKey.isEmpty {
            return LocalizedStringResource(
                "Choose an app and a letter.",
                bundle: KeyPathAppKitResources.bundle,
                comment: "Validation shown before an onboarding launcher app and shortcut letter are selected."
            )
        }
        if selectedApp == nil {
            return LocalizedStringResource(
                "Choose an app to launch.",
                bundle: KeyPathAppKitResources.bundle,
                comment: "Validation shown when an onboarding launcher letter is selected without an app."
            )
        }
        if canonicalKey.isEmpty {
            return LocalizedStringResource(
                "Choose one letter for the shortcut.",
                bundle: KeyPathAppKitResources.bundle,
                comment: "Validation shown when an onboarding launcher app is selected without a shortcut letter."
            )
        }
        guard Self.isSingleLetter(displayedKey),
              Self.normalizedLauncherKey(from: canonicalKey) != nil
        else {
            return LocalizedStringResource(
                "Use a single letter.",
                bundle: KeyPathAppKitResources.bundle,
                comment: "Validation shown when the onboarding launcher shortcut is not one supported key."
            )
        }
        if occupiedCanonicalKeys.contains(canonicalKey) {
            return LocalizedStringResource(
                "That letter already has a shortcut. Choose another.",
                bundle: KeyPathAppKitResources.bundle,
                comment: "Validation shown when the onboarding launcher shortcut letter is already assigned."
            )
        }
        return nil
    }

    private static func normalizedLauncherKey(from key: String) -> String? {
        let candidate = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard LauncherGridConfig.isValidKey(candidate) else { return nil }
        return LauncherGridConfig.normalizeKey(candidate)
    }

    private static func isSingleLetter(_ value: String) -> Bool {
        let graphemes = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard graphemes.count == 1 else { return false }
        return graphemes.unicodeScalars.allSatisfy(CharacterSet.letters.contains)
    }
}

/// Compact app-and-letter control sized for the onboarding copy column.
struct FirstSuccessLauncherChoiceView: View {
    let model: FirstSuccessLauncherChoiceModel
    let isEnabled: Bool

    @State private var isAppPickerPresented = false
    @State private var browseAfterPickerDismisses = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FirstSuccessChosenAppRow(
                selectedApp: model.selectedApp,
                chooseApp: { isAppPickerPresented = true }
            )
            FirstSuccessLauncherShortcutField(model: model)

            if let validationMessage = model.validationMessage {
                Label {
                    Text(validationMessage)
                } icon: {
                    Image(systemName: "info.circle")
                        .accessibilityHidden(true)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("first-success-launcher-validation")
            }
        }
        .padding(12)
        .frame(maxWidth: 370, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .disabled(!isEnabled)
        .sheet(
            isPresented: $isAppPickerPresented,
            onDismiss: browseForApplicationIfRequested
        ) {
            FirstSuccessRunningAppPicker(
                selectApp: { selectedApp in
                    model.selectedApp = selectedApp
                    isAppPickerPresented = false
                },
                browse: {
                    browseAfterPickerDismisses = true
                    isAppPickerPresented = false
                }
            )
        }
    }

    private func browseForApplicationIfRequested() {
        guard browseAfterPickerDismisses else { return }
        browseAfterPickerDismisses = false
        Task { @MainActor in
            if let selectedApp = await FirstSuccessApplicationBrowser.chooseApplication() {
                model.selectedApp = selectedApp
            }
        }
    }
}

private struct FirstSuccessChosenAppRow: View {
    let selectedApp: AppLaunchInfo?
    let chooseApp: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            FirstSuccessChosenAppIdentity(selectedApp: selectedApp)
            Spacer(minLength: 8)
            Button {
                chooseApp()
            } label: {
                Text(
                    selectedApp == nil ? "Choose App" : "Change",
                    bundle: KeyPathAppKitResources.bundle,
                    comment: "Button that opens the onboarding application picker."
                )
            }
            .controlSize(.small)
            .accessibilityIdentifier("first-success-launcher-choose-app")
            .accessibilityLabel(
                Text(
                    "Choose an app to launch",
                    bundle: KeyPathAppKitResources.bundle,
                    comment: "Accessibility label for the onboarding application picker button."
                )
            )
        }
    }
}

private struct FirstSuccessChosenAppIdentity: View {
    let selectedApp: AppLaunchInfo?

    var body: some View {
        HStack(spacing: 9) {
            if let selectedApp {
                Image(nsImage: selectedApp.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .accessibilityHidden(true)
                Text(selectedApp.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            } else {
                Image(systemName: "app.dashed")
                    .frame(width: 28, height: 28)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(
                    "Favorite app",
                    bundle: KeyPathAppKitResources.bundle,
                    comment: "Placeholder shown before an onboarding launcher app is selected."
                )
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct FirstSuccessLauncherShortcutField: View {
    let model: FirstSuccessLauncherChoiceModel

    @State private var displayKey = ""
    @AppStorage(KeymapPreferences.keymapIdKey)
    private var selectedKeymapID: String = LogicalKeymap.defaultId
    @AppStorage(KeymapPreferences.includePunctuationStoreKey)
    private var includePunctuationStore = "{}"

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    "Shortcut letter",
                    bundle: KeyPathAppKitResources.bundle,
                    comment: "Label for the onboarding Quick Launcher shortcut letter field."
                )
                .font(.subheadline.weight(.medium))
                Text(
                    "Hold Caps Lock, then press",
                    bundle: KeyPathAppKitResources.bundle,
                    comment: "Gesture reminder beside the onboarding Quick Launcher shortcut letter field."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text("Hyper +", bundle: KeyPathAppKitResources.bundle)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(
                "Q",
                text: $displayKey,
                prompt: Text(
                    "Q",
                    bundle: KeyPathAppKitResources.bundle,
                    comment: "Example letter in the onboarding Quick Launcher shortcut field."
                )
            )
            .textFieldStyle(.roundedBorder)
            .font(.body.monospaced().weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(width: 42)
            .accessibilityIdentifier("first-success-launcher-key-field")
            .accessibilityLabel(
                Text(
                    "Shortcut letter",
                    bundle: KeyPathAppKitResources.bundle,
                    comment: "Accessibility label for the onboarding Quick Launcher shortcut field."
                )
            )
            .accessibilityHint(
                Text(
                    "Enter one letter to press while holding Caps Lock.",
                    bundle: KeyPathAppKitResources.bundle,
                    comment: "Accessibility hint for the onboarding Quick Launcher shortcut field."
                )
            )
        }
        .onAppear(perform: synchronizeDisplayKey)
        .onChange(of: model.canonicalKey) {
            synchronizeDisplayKey()
        }
        .onChange(of: selectedKeymapID) {
            synchronizeDisplayKey()
        }
        .onChange(of: includePunctuationStore) {
            synchronizeDisplayKey()
        }
        .onChange(of: displayKey) {
            updateCanonicalKey(from: displayKey)
        }
    }

    private var keyTranslator: LauncherKeymapTranslator {
        LauncherKeymapTranslator(
            keymapId: selectedKeymapID,
            includePunctuationStore: includePunctuationStore
        )
    }

    private func synchronizeDisplayKey() {
        let translated = model.canonicalKey.isEmpty
            ? ""
            : keyTranslator.displayLabel(for: model.canonicalKey)
        model.setCanonicalKey(model.canonicalKey, displayedAs: translated)
        if displayKey != translated {
            displayKey = translated
        }
    }

    private func updateCanonicalKey(from displayValue: String) {
        let existingDisplayValue = model.canonicalKey.isEmpty
            ? ""
            : keyTranslator.displayLabel(for: model.canonicalKey)
        let singleCharacter = FirstSuccessLauncherChoiceModel.replacementDisplayGrapheme(
            from: displayValue,
            replacing: existingDisplayValue
        )
        if displayKey != singleCharacter {
            displayKey = singleCharacter
        }

        guard !singleCharacter.isEmpty else {
            model.setCanonicalKey("")
            return
        }

        if let canonical = keyTranslator.canonicalKey(for: singleCharacter) {
            model.setCanonicalKey(canonical, displayedAs: singleCharacter)
        } else {
            model.setCanonicalKey(singleCharacter, displayedAs: singleCharacter)
        }
    }
}

private struct FirstSuccessRunningAppPicker: View {
    let selectApp: (AppLaunchInfo) -> Void
    let browse: () -> Void

    @State private var runningApps: [FirstSuccessRunningAppChoice] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            FirstSuccessRunningAppPickerHeader(cancel: { dismiss() })
            Divider()
            ScrollView {
                LazyVStack(spacing: 2) {
                    if runningApps.isEmpty {
                        Text(
                            "No user-facing apps are running.",
                            bundle: KeyPathAppKitResources.bundle,
                            comment: "Empty state in the onboarding running-app picker."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        ForEach(runningApps) { choice in
                            FirstSuccessRunningAppRow(
                                choice: choice,
                                select: { selectApp(choice.app) }
                            )
                        }
                    }
                }
                .padding(8)
            }
            Divider()
            Button {
                browse()
            } label: {
                Label {
                    Text(
                        "Browse for another app…",
                        bundle: KeyPathAppKitResources.bundle,
                        comment: "Button that opens a file picker from the onboarding running-app sheet."
                    )
                } icon: {
                    Image(systemName: "folder")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(12)
            .accessibilityIdentifier("first-success-launcher-browse-app")
        }
        .frame(width: 330, height: 390)
        .accessibilityIdentifier("first-success-launcher-running-app-picker")
        .onAppear {
            runningApps = FirstSuccessRunningAppChoice.currentChoices()
        }
    }
}

private struct FirstSuccessRunningAppPickerHeader: View {
    let cancel: () -> Void

    var body: some View {
        HStack {
            Text(
                "Choose an App",
                bundle: KeyPathAppKitResources.bundle,
                comment: "Title of the onboarding running-app picker."
            )
            .font(.headline)
            Spacer()
            Button(action: cancel) {
                Text(
                    "Cancel",
                    bundle: KeyPathAppKitResources.bundle,
                    comment: "Button that closes the onboarding running-app picker."
                )
            }
            .accessibilityIdentifier("first-success-launcher-app-picker-cancel")
        }
        .padding(14)
    }
}

private struct FirstSuccessRunningAppRow: View {
    let choice: FirstSuccessRunningAppChoice
    let select: () -> Void

    var body: some View {
        Button {
            select()
        } label: {
            HStack(spacing: 10) {
                Image(nsImage: choice.app.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .accessibilityHidden(true)
                Text(choice.app.name)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("first-success-launcher-running-app-\(choice.id)")
        .accessibilityLabel(
            Text(
                "Choose \(choice.app.name)",
                bundle: KeyPathAppKitResources.bundle,
                comment: "Running-app picker row. The variable is the application name."
            )
        )
        .accessibilityHint(
            Text(
                "Uses this app for the new launcher shortcut.",
                bundle: KeyPathAppKitResources.bundle,
                comment: "Accessibility hint for an onboarding running-app picker row."
            )
        )
    }
}

private struct FirstSuccessRunningAppChoice: Identifiable {
    let id: String
    let app: AppLaunchInfo

    @MainActor
    static func currentChoices() -> [FirstSuccessRunningAppChoice] {
        var seenIdentifiers: Set<String> = []
        let currentBundleIdentifier = Bundle.main.bundleIdentifier

        return NSWorkspace.shared.runningApplications
            .filter { runningApp in
                runningApp.activationPolicy == .regular &&
                    runningApp.bundleIdentifier != currentBundleIdentifier &&
                    runningApp.localizedName != nil
            }
            .compactMap { runningApp -> FirstSuccessRunningAppChoice? in
                guard let name = runningApp.localizedName else { return nil }
                let identifier = runningApp.bundleIdentifier
                    ?? "process-\(runningApp.processIdentifier)"
                guard seenIdentifiers.insert(identifier).inserted else { return nil }

                return FirstSuccessRunningAppChoice(
                    id: identifier,
                    app: AppLaunchInfo(
                        name: name,
                        bundleIdentifier: runningApp.bundleIdentifier,
                        icon: preparedIcon(runningApp.icon, accessibilityDescription: name)
                    )
                )
            }
            .sorted {
                $0.app.name.localizedCaseInsensitiveCompare($1.app.name) == .orderedAscending
            }
    }

    @MainActor
    private static func preparedIcon(
        _ source: NSImage?,
        accessibilityDescription: String
    ) -> NSImage {
        let fallback = NSImage(
            systemSymbolName: "app",
            accessibilityDescription: accessibilityDescription
        ) ?? NSImage()
        let icon = (source?.copy() as? NSImage) ?? fallback
        icon.size = NSSize(width: 28, height: 28)
        return icon
    }
}

@MainActor
private enum FirstSuccessApplicationBrowser {
    static func chooseApplication() async -> AppLaunchInfo? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.message = String(
            localized: "Choose the app this shortcut should open.",
            bundle: KeyPathAppKitResources.bundle,
            comment: "Message in the onboarding application file picker."
        )
        panel.prompt = String(
            localized: "Choose App",
            bundle: KeyPathAppKitResources.bundle,
            comment: "Confirmation button in the onboarding application file picker."
        )

        let response = await withCheckedContinuation { continuation in
            panel.begin { result in
                continuation.resume(returning: result)
            }
        }
        guard response == .OK, let applicationURL = panel.url else { return nil }

        let name = applicationURL.deletingPathExtension().lastPathComponent
        let sourceIcon = NSWorkspace.shared.icon(forFile: applicationURL.path)
        let icon = (sourceIcon.copy() as? NSImage) ?? sourceIcon
        icon.size = NSSize(width: 28, height: 28)
        return AppLaunchInfo(
            name: name,
            bundleIdentifier: Bundle(url: applicationURL)?.bundleIdentifier,
            icon: icon
        )
    }
}
