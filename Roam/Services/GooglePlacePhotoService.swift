import Foundation
import os.log
import UIKit

/// Loads a venue photo via Google **Places API (legacy)** HTTP endpoints using `GOOGLE_MAPS_IOS_API_KEY`.
///
/// Flow: **Place Details** (when Roam exposes `googlePlaceId`) → **Find Place** → **Text Search**,
/// because Find Place often omits `photos` until you call Details.
enum GooglePlacePhotoService {
    private static let log = Logger(subsystem: "Roam", category: "GooglePlacePhoto")

    private static let detailsEndpoint = "https://maps.googleapis.com/maps/api/place/details/json"
    private static let findPlaceEndpoint = "https://maps.googleapis.com/maps/api/place/findplacefromtext/json"
    private static let textSearchEndpoint = "https://maps.googleapis.com/maps/api/place/textsearch/json"
    private static let photoEndpoint = "https://maps.googleapis.com/maps/api/place/photo"

    private struct PlacePhotoMeta: Decodable {
        let photoReference: String

        enum CodingKeys: String, CodingKey {
            case photoReference = "photo_reference"
        }
    }

    private struct PlaceDetailsResponse: Decodable {
        let result: ResultBody?
        let status: String
        let errorMessage: String?

        struct ResultBody: Decodable {
            let photos: [PlacePhotoMeta]?
        }

        enum CodingKeys: String, CodingKey {
            case result, status
            case errorMessage = "error_message"
        }
    }

    private struct FindPlaceResponse: Decodable {
        let candidates: [FindCandidate]?
        let status: String
        let errorMessage: String?

        struct FindCandidate: Decodable {
            let placeId: String?
            let photos: [PlacePhotoMeta]?

            enum CodingKeys: String, CodingKey {
                case placeId = "place_id"
                case photos
            }
        }

        enum CodingKeys: String, CodingKey {
            case candidates, status
            case errorMessage = "error_message"
        }
    }

    private struct TextSearchResponse: Decodable {
        let results: [TextHit]?
        let status: String
        let errorMessage: String?

        struct TextHit: Decodable {
            let placeId: String?
            let photos: [PlacePhotoMeta]?

            enum CodingKeys: String, CodingKey {
                case placeId = "place_id"
                case photos
            }
        }

        enum CodingKeys: String, CodingKey {
            case results, status
            case errorMessage = "error_message"
        }
    }

    static func mapsAPIKey() -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_MAPS_IOS_API_KEY") as? String else { return nil }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    /// - Parameters:
    ///   - googlePlaceId: When set (from Roam `places.google_place_id`), uses Place Details first — most reliable.
    static func fetchPlaceHeroUIImage(
        googlePlaceId: String?,
        searchQuery: String,
        latitude: Double?,
        longitude: Double?
    ) async -> UIImage? {
        guard let apiKey = mapsAPIKey() else {
            logDebug("No GOOGLE_MAPS_IOS_API_KEY in Info.plist")
            return nil
        }

        let gid = googlePlaceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gid.isEmpty || !query.isEmpty else { return nil }

        if !gid.isEmpty {
            if let ref = await photoReferenceFromPlaceDetails(placeId: gid, apiKey: apiKey),
               let image = await loadPhotoImage(photoReference: ref, apiKey: apiKey) {
                return image
            }
        }

        if !query.isEmpty {
            if let ref = await photoReferenceFromFindPlace(
                input: query,
                latitude: latitude,
                longitude: longitude,
                apiKey: apiKey
            ), let image = await loadPhotoImage(photoReference: ref, apiKey: apiKey) {
                return image
            }

            if let ref = await photoReferenceFromTextSearch(
                query: query,
                latitude: latitude,
                longitude: longitude,
                apiKey: apiKey
            ), let image = await loadPhotoImage(photoReference: ref, apiKey: apiKey) {
                return image
            }
        }

        return nil
    }

    // MARK: - Place Details

    private static func photoReferenceFromPlaceDetails(placeId: String, apiKey: String) async -> String? {
        var components = URLComponents(string: detailsEndpoint)
        components?.queryItems = [
            URLQueryItem(name: "place_id", value: placeId),
            URLQueryItem(name: "fields", value: "photos"),
            URLQueryItem(name: "key", value: apiKey)
        ]
        guard let url = components?.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            let decoded = try JSONDecoder().decode(PlaceDetailsResponse.self, from: data)
            logDebug("Place Details status=\(decoded.status) msg=\(decoded.errorMessage ?? "—")")
            guard decoded.status == "OK" else { return nil }
            return decoded.result?.photos?.first?.photoReference
        } catch {
            logDebug("Place Details decode error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Find Place

    private static func photoReferenceFromFindPlace(
        input: String,
        latitude: Double?,
        longitude: Double?,
        apiKey: String
    ) async -> String? {
        var components = URLComponents(string: findPlaceEndpoint)
        var items: [URLQueryItem] = [
            URLQueryItem(name: "fields", value: "place_id,photos"),
            URLQueryItem(name: "input", value: input),
            URLQueryItem(name: "inputtype", value: "textquery"),
            URLQueryItem(name: "key", value: apiKey)
        ]
        if let lat = latitude, let lng = longitude {
            let bias = "circle:2000@\(formatCoord(lat)),\(formatCoord(lng))"
            items.append(URLQueryItem(name: "locationbias", value: bias))
        }
        components?.queryItems = items
        guard let url = components?.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            let decoded = try JSONDecoder().decode(FindPlaceResponse.self, from: data)
            logDebug("Find Place status=\(decoded.status) msg=\(decoded.errorMessage ?? "—")")
            guard decoded.status == "OK", let first = decoded.candidates?.first else { return nil }
            if let ref = first.photos?.first?.photoReference { return ref }
            if let pid = first.placeId, !pid.isEmpty {
                return await photoReferenceFromPlaceDetails(placeId: pid, apiKey: apiKey)
            }
            return nil
        } catch {
            logDebug("Find Place error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Text Search (fallback)

    private static func photoReferenceFromTextSearch(
        query: String,
        latitude: Double?,
        longitude: Double?,
        apiKey: String
    ) async -> String? {
        var components = URLComponents(string: textSearchEndpoint)
        var items: [URLQueryItem] = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "key", value: apiKey)
        ]
        if let lat = latitude, let lng = longitude {
            items.append(URLQueryItem(name: "location", value: "\(formatCoord(lat)),\(formatCoord(lng))"))
            items.append(URLQueryItem(name: "radius", value: "5000"))
        }
        components?.queryItems = items
        guard let url = components?.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            let decoded = try JSONDecoder().decode(TextSearchResponse.self, from: data)
            logDebug("Text Search status=\(decoded.status) msg=\(decoded.errorMessage ?? "—")")
            guard decoded.status == "OK", let first = decoded.results?.first else { return nil }
            if let ref = first.photos?.first?.photoReference { return ref }
            if let pid = first.placeId, !pid.isEmpty {
                return await photoReferenceFromPlaceDetails(placeId: pid, apiKey: apiKey)
            }
            return nil
        } catch {
            logDebug("Text Search error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Photo bytes

    private static func loadPhotoImage(photoReference: String, apiKey: String) async -> UIImage? {
        var components = URLComponents(string: photoEndpoint)
        components?.queryItems = [
            URLQueryItem(name: "maxwidth", value: "800"),
            URLQueryItem(name: "photo_reference", value: photoReference),
            URLQueryItem(name: "key", value: apiKey)
        ]
        guard let url = components?.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            guard !data.isEmpty, let image = UIImage(data: data) else { return nil }
            return image
        } catch {
            return nil
        }
    }

    private static func formatCoord(_ d: Double) -> String {
        String(format: "%.7f", locale: Locale(identifier: "en_US_POSIX"), d)
    }

    private static func logDebug(_ message: String) {
        #if DEBUG
        log.debug("\(message, privacy: .public)")
        #endif
    }
}
