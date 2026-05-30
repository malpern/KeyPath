import AppIntents
import Foundation

struct LayerEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Layer")
    static let defaultQuery = LayerEntityQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct LayerEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [LayerEntity] {
        let allLayers = await (try? fetchLayers()) ?? []
        return allLayers.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [LayerEntity] {
        await (try? fetchLayers()) ?? []
    }

    private func fetchLayers() async throws -> [LayerEntity] {
        let facade = ConfigFacade()
        let names = try await facade.tcpGetLayers()
        return names.map { LayerEntity(id: $0, name: $0) }
    }
}
