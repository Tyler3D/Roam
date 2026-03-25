import SwiftUI

struct MapPage: View {
    @Environment(\.roamStores) private var stores

    var body: some View {
        CollectionMapExplorerView()
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await stores.mapCollections.refreshCollections()
                await stores.mapCollections.refreshPins()
                await stores.mapCollections.prefetchAllPins()
            }
    }
}
