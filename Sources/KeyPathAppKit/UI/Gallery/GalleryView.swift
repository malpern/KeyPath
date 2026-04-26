// M1 Gallery MVP — the Gallery view.
// Spec: docs/design/sprint-1/gallery-and-cards.md, simplified per
// docs/design/m1-implementation-plan.md (no Discover/Categories/My Packs
// split; single list of 3 packs).

import KeyPathCore
import SwiftUI

/// The Gallery. M1 = a single section showing the three Starter Kit packs.
/// No Discover/Categories/My Packs tabs, no search, no categories.
///
/// Opens as a sheet on top of the main window; dismissed by ✕ or Esc.
struct GalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(KanataViewModel.self) private var kanataManager

    @State private var installedIDs: Set<String> = []
    @State private var packForDetail: Pack?
    @State private var busyPackIDs: Set<String> = []
    @State private var installAlert: InstallAlert?
    @State private var packConflict: PackConflictState?

    private struct InstallAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let websiteURL: URL?
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().padding(.horizontal, 24)
            content
        }
        .frame(minWidth: 560, idealWidth: 780, minHeight: 420, idealHeight: 520)
        .task {
            await refreshInstalledIDs()
        }
        .sheet(item: $packForDetail, onDismiss: { Task { await refreshInstalledIDs() } }) { pack in
            PackDetailView(pack: pack)
                .environment(kanataManager)
        }
        .alert(
            installAlert?.title ?? "",
            isPresented: Binding(
                get: { installAlert != nil },
                set: { if !$0 { installAlert = nil } }
            ),
            presenting: installAlert,
            actions: { alert in
                if let url = alert.websiteURL {
                    Button("Get KindaVim →") {
                        NSWorkspace.shared.open(url)
                    }
                    .accessibilityIdentifier("gallery-install-alert-get-kindavim")
                    Button("Cancel", role: .cancel) {}
                        .accessibilityIdentifier("gallery-install-alert-cancel")
                } else {
                    Button("OK", role: .cancel) {}
                        .accessibilityIdentifier("gallery-install-alert-ok")
                }
            },
            message: { alert in Text(alert.message) }
        )
        .sheet(item: $packConflict) { conflict in
            PackConflictResolutionDialog(
                state: conflict,
                onChoice: { choice in
                    packConflict = nil
                    if choice == .switchToNew {
                        Task { await resolveConflictAndInstall(conflict) }
                    }
                },
                onCancel: { packConflict = nil }
            )
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Gallery")
                    .font(.system(size: 22, weight: .semibold))
                Text("Ready-made packs of mappings. One click on; one click off.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(.quaternary))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close Gallery")
            .accessibilityIdentifier("gallery-close")
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    private var content: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sections, id: \.title) { section in
                    sectionView(section)
                }
            }
            .padding(.bottom, 24)
        }
    }

    /// Groups packs by category for the Gallery's sectioned layout, mirroring
    /// how the Rules tab organizes its built-in collections.
    private var sections: [(title: String, packs: [Pack])] {
        let grouped = Dictionary(grouping: PackRegistry.starterKit, by: \.category)
        // Preserve the order packs appear in `starterKit` for stable
        // presentation, then sort categories by the first pack's position.
        let orderedCategories: [String] = {
            var seen = Set<String>()
            var order: [String] = []
            for pack in PackRegistry.starterKit where !seen.contains(pack.category) {
                seen.insert(pack.category)
                order.append(pack.category)
            }
            return order
        }()
        return orderedCategories.compactMap { title in
            guard let packs = grouped[title] else { return nil }
            return (title: title, packs: packs)
        }
    }

    private func sectionView(_ section: (title: String, packs: [Pack])) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.title)
                .font(.system(size: 16, weight: .semibold))
                .padding(.top, 20)
                .padding(.horizontal, 24)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 260, maximum: 300), spacing: 18, alignment: .top)],
                alignment: .leading,
                spacing: 18
            ) {
                ForEach(section.packs) { pack in
                    PackCardView(
                        pack: pack,
                        isInstalled: installedIDs.contains(pack.id),
                        onSelect: { packForDetail = pack },
                        onToggle: { newValue in
                            Task { await togglePack(pack, to: newValue) }
                        },
                        isToggleBusy: busyPackIDs.contains(pack.id)
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
    }

    // MARK: - State

    private func refreshInstalledIDs() async {
        let installed = await InstalledPackTracker.shared.allInstalled()
        await MainActor.run {
            installedIDs = Set(installed.map(\.packID))
        }
    }

    /// Inline install/uninstall triggered by the card's toggle. Mirrors
    /// the Pack Detail toggle but lets users flip a pack on/off without
    /// opening the sheet.
    ///
    /// The UI flips optimistically: `installedIDs` is updated on tap, then
    /// the install/uninstall runs. On failure, we re-sync from the tracker
    /// so the toggle snaps back to truth. `busyPackIDs` is still tracked so
    /// a rapid second tap during the in-flight work can be ignored.
    private func togglePack(_ pack: Pack, to newValue: Bool) async {
        let manager = kanataManager.underlyingManager.ruleCollectionsManager
        await MainActor.run {
            _ = busyPackIDs.insert(pack.id)
            if newValue {
                installedIDs.insert(pack.id)
            } else {
                installedIDs.remove(pack.id)
            }
        }
        defer { Task { @MainActor in busyPackIDs.remove(pack.id) } }
        do {
            if newValue {
                _ = try await PackInstaller.shared.install(pack, manager: manager)
            } else {
                try await PackInstaller.shared.uninstall(packID: pack.id, manager: manager)
            }
            // Reconcile with truth in case the installer added/removed more
            // than we optimistically tracked.
            await refreshInstalledIDs()
        } catch {
            AppLogger.shared.log(
                "⚠️ [Gallery] Toggle failed for pack '\(pack.id)': \(error.localizedDescription)"
            )
            await presentAlert(for: error, pack: pack)
            await refreshInstalledIDs()
        }
    }

    private func resolveConflictAndInstall(_ conflict: PackConflictState) async {
        let manager = kanataManager.underlyingManager.ruleCollectionsManager
        do {
            for conflicting in conflict.conflictingPacks {
                try await PackInstaller.shared.uninstall(packID: conflicting.id, manager: manager)
            }
            _ = try await PackInstaller.shared.install(conflict.packToInstall, manager: manager)
        } catch {
            AppLogger.shared.log(
                "⚠️ [Gallery] Conflict resolution failed: \(error.localizedDescription)"
            )
        }
        await refreshInstalledIDs()
    }

    private func presentAlert(for error: Error, pack: Pack) async {
        let alert: InstallAlert
        if let installError = error as? PackInstaller.InstallError {
            switch installError {
            case let .dependencyMissing(name, url):
                alert = InstallAlert(
                    title: "\(name) isn't installed",
                    message:
                        "“\(pack.name)” needs the \(name) app to be installed first. " +
                        "It's a separate macOS app that handles Vim modes; KeyPath just shows you which keys are active.",
                    websiteURL: url
                )
            case let .mutuallyExclusive(conflicts):
                await MainActor.run {
                    packConflict = PackConflictState(
                        packToInstall: pack,
                        conflictingPacks: conflicts
                    )
                }
                return
            case .noRuleCollectionsManager, .saveFailed:
                return
            }
        } else {
            return
        }
        await MainActor.run { installAlert = alert }
    }
}
