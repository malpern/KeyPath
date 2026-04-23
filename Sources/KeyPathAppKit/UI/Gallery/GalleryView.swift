// M1 Gallery MVP — the Gallery view.
// Spec: docs/design/sprint-1/gallery-and-cards.md, simplified per
// docs/design/m1-implementation-plan.md (no Discover/Categories/My Packs
// split; single list of 3 packs).

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
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Gallery")
                    .font(.system(size: 22, weight: .semibold))
                Text("Ready-made packs of mappings. One click to install; one click to undo.")
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
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    private var content: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Start here")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.top, 18)
                    .padding(.horizontal, 24)

                Text("Three packs to get started. Each one is undoable if you don't like it.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 240, maximum: 280), spacing: 16, alignment: .top)],
                    alignment: .leading,
                    spacing: 16
                ) {
                    ForEach(PackRegistry.starterKit) { pack in
                        PackCardView(
                            pack: pack,
                            isInstalled: installedIDs.contains(pack.id),
                            onSelect: { packForDetail = pack }
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: - State

    private func refreshInstalledIDs() async {
        let installed = await InstalledPackTracker.shared.allInstalled()
        await MainActor.run {
            installedIDs = Set(installed.map(\.packID))
        }
    }
}
