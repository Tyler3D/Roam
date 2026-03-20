import MapKit
import SwiftUI

struct MapPage: View {
    @Environment(\.roamStores) private var stores
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        mapContent(stores: stores)
            .navigationTitle("map")
            .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func mapContent(stores: RoamStores) -> some View {
        let pins = stores.ideas.ideas.compactMap { idea -> IdeaMapPin? in
            guard let lat = idea.placeLatitude, let lng = idea.placeLongitude else { return nil }
            return IdeaMapPin(
                id: idea.id,
                title: (idea.displayName?.isEmpty == false ? idea.displayName! : idea.title),
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng)
            )
        }

        ZStack {
            if stores.ideas.isLoading && stores.ideas.ideas.isEmpty {
                ProgressView("loading map…")
                    .tint(RoamColors.loganDeep)
            } else if pins.isEmpty {
                RoamEmptyState(
                    icon: "◎",
                    title: "no pins yet",
                    subtitle: "enrich ideas with places to see them on the map"
                )
                .padding(.top, 40)
            } else {
                Map(position: $position) {
                    ForEach(pins) { pin in
                        Marker(pin.title, coordinate: pin.coordinate)
                            .tint(RoamColors.loganDeep)
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await stores.ideas.loadIfStale() }
    }
}

private struct IdeaMapPin: Identifiable {
    let id: String
    let title: String
    let coordinate: CLLocationCoordinate2D
}
