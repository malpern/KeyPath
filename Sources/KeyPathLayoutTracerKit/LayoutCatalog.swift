import Foundation

struct LayoutCatalogEntry: Identifiable, Equatable {
    var id: String { fileURL.path }
    let fileURL: URL
    let filename: String
    let layoutID: String
    let displayName: String
}

enum LayoutCatalog {
    static func builtInLayouts() -> [LayoutCatalogEntry] {
        let manager = FileManager.default
        guard let resourcesURL = bundledLayoutsDirectoryURL(),
              let files = try? manager.contentsOfDirectory(
                at: resourcesURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              )
        else {
            return []
        }

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap(entry(for:))
            .sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    private static func entry(for url: URL) -> LayoutCatalogEntry? {
        let filename = url.deletingPathExtension().lastPathComponent
        let data = try? Data(contentsOf: url)
        let imported = data.flatMap { try? LayoutTracerImporter.load(from: $0) }
        return LayoutCatalogEntry(
            fileURL: url,
            filename: filename,
            layoutID: imported?.id ?? filename,
            displayName: imported?.name ?? filename
        )
    }

    private static func bundledLayoutsDirectoryURL() -> URL? {
        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let repoRoot = sourceFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return repoRoot.appendingPathComponent("Sources/KeyPathAppKit/Resources/Keyboards", isDirectory: true)
    }
}
