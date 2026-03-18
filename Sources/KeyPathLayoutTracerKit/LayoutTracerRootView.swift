import AppKit
import SwiftUI

struct LayoutTracerRootView: View {
    @State private var document = TracingDocument()
    @State private var documentError: String?
    @StateObject private var menuState = LayoutTracerMenuState.shared
    @State private var saveSheetMode: SaveSheetMode?
    private let availableLayouts = LayoutCatalog.builtInLayouts()

    private enum SaveSheetMode: Identifiable {
        case save
        case saveAs

        var id: String {
            switch self {
            case .save: "save"
            case .saveAs: "saveAs"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            LayoutTracerInspectorView(
                document: document,
                onOpenImage: openImage,
                onClearImage: clearImage,
                onOpenLayout: openLayout,
                availableLayouts: availableLayouts,
                onSelectLayout: { layout in
                    loadLayout(from: layout.fileURL)
                }
            )
        } detail: {
            LayoutTracerCanvasView(document: document)
        }
        .navigationSplitViewStyle(.balanced)
        .alert("Document Error", isPresented: Binding(get: { documentError != nil }, set: { if !$0 { documentError = nil } })) {
            Button("OK", role: .cancel) {}
                .accessibilityIdentifier("layoutTracer.exportError.ok")
        } message: {
            Text(documentError ?? "Unknown error")
        }
        .sheet(item: $saveSheetMode) { mode in
            LayoutSaveSheet(
                title: mode == .save ? "Save Layout" : "Save Layout As",
                confirmTitle: mode == .save ? "Save" : "Continue",
                layoutID: document.layoutID,
                layoutName: document.layoutName
            ) { layoutID, layoutName in
                document.updateLayoutMetadata(id: layoutID, name: layoutName)
                if mode == .save {
                    performSave()
                } else {
                    performSaveAs()
                }
            }
        }
        .onAppear(perform: syncMenuState)
        .onChange(of: document.canUndo) { _, _ in syncMenuState() }
        .onChange(of: document.canRedo) { _, _ in syncMenuState() }
        .onChange(of: document.layoutFileURL) { _, _ in syncMenuState() }
        .onChange(of: document.hasGuides) { _, _ in syncMenuState() }
        .onChange(of: document.snapEnabled) { _, _ in syncMenuState() }
        .onChange(of: document.showsSnapGuides) { _, _ in syncMenuState() }
    }

    private func openImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadImage(from: url)
    }

    private func openLayout() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadLayout(from: url)
    }

    private func loadImage(from url: URL) {
        do {
            try document.loadImage(from: url)
            document.fitCanvasToViewport()
        } catch {
            documentError = error.localizedDescription
        }
    }

    private func clearImage() {
        document.clearImage()
    }

    private func loadLayout(from url: URL) {
        do {
            try document.loadLayout(from: url)
            document.fitCanvasToViewport()
        } catch {
            documentError = error.localizedDescription
        }
    }

    private func saveJSON() {
        saveSheetMode = .save
    }

    private func saveJSONAs() {
        saveSheetMode = .saveAs
    }

    private func performSave() {
        do {
            if document.layoutFileURL == nil {
                performSaveAs()
            } else {
                try document.save()
            }
        } catch {
            documentError = error.localizedDescription
        }
    }

    private func performSaveAs() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(document.layoutID).json"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try document.save(to: url)
        } catch {
            documentError = error.localizedDescription
        }
    }

    @MainActor
    private func syncMenuState() {
        menuState.canSave = document.layoutFileURL != nil
        menuState.canUndo = document.canUndo
        menuState.canRedo = document.canRedo
        menuState.canClearGuides = document.hasGuides
        menuState.snapEnabled = document.snapEnabled
        menuState.showsSnapGuides = document.showsSnapGuides
        menuState.save = saveJSON
        menuState.saveAs = saveJSONAs
        menuState.undo = { document.undo() }
        menuState.redo = { document.redo() }
        menuState.clearGuides = { document.clearGuides() }
        menuState.setSnapEnabled = { document.snapEnabled = $0 }
        menuState.setShowsSnapGuides = { document.showsSnapGuides = $0 }
    }
}
