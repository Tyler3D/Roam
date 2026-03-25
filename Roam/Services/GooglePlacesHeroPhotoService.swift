import CoreLocation
import GooglePlacesSwift
import UIKit

/// Hero image via **Places SDK for iOS (New)** — works with bundle-restricted `GOOGLE_MAPS_IOS_API_KEY`.
/// `PlacesClient.provideAPIKey` must run at launch (`GoogleMapsBootstrap`).
enum GooglePlacesHeroPhotoService {
    private static let photoMaxDimension: CGFloat = 1600

    /// Same inputs as `GooglePlacePhotoService.fetchPlaceHeroUIImage`; must run on the main actor (`PlacesClient` requirement).
    @MainActor
    static func fetchPlaceHeroUIImage(
        googlePlaceId: String?,
        searchQuery: String,
        latitude: Double?,
        longitude: Double?
    ) async -> UIImage? {
        guard GooglePlacePhotoService.mapsAPIKey() != nil else { return nil }

        let gid = googlePlaceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gid.isEmpty || !query.isEmpty else { return nil }

        let client = PlacesClient.shared

        if !gid.isEmpty {
            if let image = await fetchPhotoForPlaceId(client: client, placeId: gid) {
                return image
            }
        }

        if !query.isEmpty,
           let lat = latitude,
           let lng = longitude {
            if let image = await fetchPhotoForTextQuery(
                client: client,
                query: query,
                latitude: lat,
                longitude: lng
            ) {
                return image
            }
        }

        return nil
    }

    @MainActor
    private static func fetchPhotoForPlaceId(client: PlacesClient, placeId: String) async -> UIImage? {
        let request = FetchPlaceRequest(placeID: placeId, placeProperties: [.photos])
        let place: Place
        switch await client.fetchPlace(with: request) {
        case .success(let p):
            place = p
        case .failure:
            return nil
        }
        guard let photo = place.photos?.first else { return nil }
        return await loadPhoto(client: client, photo: photo)
    }

    @MainActor
    private static func fetchPhotoForTextQuery(
        client: PlacesClient,
        query: String,
        latitude: Double,
        longitude: Double
    ) async -> UIImage? {
        let bias = CircularCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            radius: 5000
        )
        let request = SearchByTextRequest(
            textQuery: query,
            placeProperties: [.photos],
            locationBias: bias,
            maxResultCount: 5,
            isOpenNow: false
        )
        let places: [Place]
        switch await client.searchByText(with: request) {
        case .success(let list):
            places = list
        case .failure:
            return nil
        }
        for place in places {
            if let photo = place.photos?.first,
               let image = await loadPhoto(client: client, photo: photo) {
                return image
            }
        }
        return nil
    }

    @MainActor
    private static func loadPhoto(client: PlacesClient, photo: Photo) async -> UIImage? {
        let req = FetchPhotoRequest(
            photo: photo,
            maxSize: CGSize(width: photoMaxDimension, height: photoMaxDimension)
        )
        switch await client.fetchPhoto(with: req) {
        case .success(let uiImage):
            return uiImage
        case .failure:
            return nil
        }
    }
}
