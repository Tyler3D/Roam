import Foundation
import MapKit
import Observation
import SwiftUI

/// Drives map tab: collection chips + pins from `/api/collections/.../ideas`.
@MainActor
@Observable
final class MapCollectionsQueryStore {
    enum ChipSelection: Equatable {
        case everything
        case mySaves
        case sharedCollection(UUID)
    }

    private let api: APIClient

    private(set) var collections: [APIClient.CollectionReadDTO] = []
    private(set) var mapPins: [APIClient.CollectionMapPinDTO] = []
    private(set) var isLoadingCollections = false
    private(set) var isLoadingPins = false
    private(set) var lastError: String?

    var selection: ChipSelection = .everything

    init(api: APIClient) {
        self.api = api
    }

    var personalDefaultId: UUID? {
        collections.first(where: { $0.isPersonalDefault })?.id
    }

    var sharedCollections: [APIClient.CollectionReadDTO] {
        collections.filter { !$0.isPersonalDefault }
    }

    func loadCollectionsIfStale() async {
        if !collections.isEmpty { return }
        await refreshCollections()
    }

    func refreshCollections() async {
        isLoadingCollections = true
        lastError = nil
        defer { isLoadingCollections = false }
        do {
            collections = try await api.listCollections()
            if selection == .mySaves, personalDefaultId == nil {
                selection = .everything
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshPins() async {
        isLoadingPins = true
        lastError = nil
        defer { isLoadingPins = false }
        do {
            switch selection {
            case .everything:
                mapPins = try await api.listEverythingMapPins()
            case .mySaves:
                guard let pid = personalDefaultId else {
                    mapPins = []
                    return
                }
                mapPins = try await api.listCollectionMapPins(collectionId: pid)
            case .sharedCollection(let id):
                mapPins = try await api.listCollectionMapPins(collectionId: id)
            }
        } catch {
            lastError = error.localizedDescription
            mapPins = []
        }
    }

    func setSelection(_ newValue: ChipSelection) async {
        selection = newValue
        await refreshPins()
    }
}

enum MapPinPalette {
    static func color(forIndex index: Int) -> Color {
        let i = ((index % 8) + 8) % 8
        switch i {
        case 0: return RoamColors.loganDeep
        case 1: return RoamColors.greenDeep
        case 2: return Color(red: 0.85, green: 0.35, blue: 0.45)
        case 3: return Color(red: 0.25, green: 0.55, blue: 0.85)
        case 4: return Color(red: 0.95, green: 0.55, blue: 0.2)
        case 5: return Color(red: 0.45, green: 0.35, blue: 0.75)
        case 6: return Color(red: 0.2, green: 0.65, blue: 0.55)
        default: return Color(red: 0.55, green: 0.4, blue: 0.3)
        }
    }
}
