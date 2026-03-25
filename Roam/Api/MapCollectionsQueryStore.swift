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

    /// Per-selection pin cache so chip switching is instant.
    private var pinCache: [String: [APIClient.CollectionMapPinDTO]] = [:]

    init(api: APIClient) {
        self.api = api
    }

    private func cacheKey(for sel: ChipSelection) -> String {
        switch sel {
        case .everything: return "everything"
        case .mySaves: return "mySaves"
        case .sharedCollection(let id): return "shared:\(id.uuidString)"
        }
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
        let sel = selection
        let key = cacheKey(for: sel)
        isLoadingPins = true
        lastError = nil
        defer { isLoadingPins = false }
        do {
            let fetched: [APIClient.CollectionMapPinDTO]
            switch sel {
            case .everything:
                fetched = try await api.listEverythingMapPins()
            case .mySaves:
                guard let pid = personalDefaultId else {
                    mapPins = []
                    pinCache[key] = []
                    return
                }
                fetched = try await api.listCollectionMapPins(collectionId: pid)
            case .sharedCollection(let id):
                fetched = try await api.listCollectionMapPins(collectionId: id)
            }
            pinCache[key] = fetched
            // Only apply if the user hasn't switched away while we were loading.
            if selection == sel {
                mapPins = fetched
            }
        } catch {
            lastError = error.localizedDescription
            if selection == sel {
                mapPins = []
            }
        }
    }

    func setSelection(_ newValue: ChipSelection) async {
        // Cache outgoing pins.
        pinCache[cacheKey(for: selection)] = mapPins
        selection = newValue
        // Instantly show cached pins (or empty if first visit).
        let key = cacheKey(for: newValue)
        mapPins = pinCache[key] ?? []
        // Refresh from network in background.
        await refreshPins()
    }

    /// Clears the pin cache so the next refresh fetches fresh data for all collections.
    func invalidateCache() {
        pinCache.removeAll()
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
