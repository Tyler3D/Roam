import CoreLocation
import GoogleMaps
import SwiftUI

/// Data returned by the location picker when the user confirms a selection.
struct PickedLocation {
    let placeId: UUID?
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
}

/// A bottom-sheet style view for searching places (via Google Places Autocomplete)
/// and fine-tuning location with a centered pin over a pannable Google Maps view.
struct LocationPickerSheet: View {
    var initialQuery: String
    var initialCoordinate: CLLocationCoordinate2D?
    var onConfirm: (PickedLocation) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String = ""
    @State private var autocompletePredictions: [GooglePlacePrediction] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    @State private var selectedPrediction: GooglePlacePrediction?
    @State private var selectedPlaceDetail: GooglePlaceDetail?
    @State private var pinCoordinate: CLLocationCoordinate2D?
    @State private var mapFitToken = 0
    /// Address derived from reverse-geocoding the current pin position.
    @State private var reverseGeocodedAddress: String?
    @State private var geocodeTask: Task<Void, Never>?
    @State private var isFetchingDetail = false

    init(initialQuery: String, initialCoordinate: CLLocationCoordinate2D?, onConfirm: @escaping (PickedLocation) -> Void) {
        self.initialQuery = initialQuery
        self.initialCoordinate = initialCoordinate
        self.onConfirm = onConfirm
        _pinCoordinate = State(initialValue: initialCoordinate)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                ScrollView {
                    VStack(spacing: 12) {
                        if !autocompletePredictions.isEmpty {
                            autocompleteList
                        }
                        mapSection
                        if let detail = selectedPlaceDetail {
                            selectedAddressCard(detail)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
                confirmButton
            }
            .background(RoamColors.background)
            .navigationTitle("Set location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(RoamColors.reviewAccent)
                }
            }
        }
        .onAppear {
            searchText = initialQuery
            if !initialQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                searchTask = Task { await runAutocomplete(initialQuery) }
            }
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(RoamColors.textMuted)
            TextField("Search address or place…", text: $searchText)
                .font(.system(size: 15))
                .foregroundStyle(RoamColors.text)
                .autocorrectionDisabled()
                .onChange(of: searchText) { _, newVal in
                    searchTask?.cancel()
                    let q = newVal.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard q.count >= 2 else {
                        autocompletePredictions = []
                        return
                    }
                    searchTask = Task {
                        try? await Task.sleep(nanoseconds: 150_000_000)
                        guard !Task.isCancelled else { return }
                        await runAutocomplete(q)
                    }
                }
            if isSearching || isFetchingDetail {
                ProgressView()
                    .controlSize(.small)
            }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    autocompletePredictions = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(RoamColors.textMuted)
                }
            }
        }
        .padding(12)
        .background(RoamColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(RoamColors.reviewBorder, lineWidth: 1.5)
        )
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Autocomplete list

    private var autocompleteList: some View {
        VStack(spacing: 0) {
            ForEach(Array(autocompletePredictions.prefix(5).enumerated()), id: \.element.placeId) { index, prediction in
                Button {
                    Task { await selectPrediction(prediction) }
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selectedPrediction?.placeId == prediction.placeId
                                      ? RoamColors.reviewSuccess.opacity(0.12)
                                      : RoamColors.reviewAccent.opacity(0.08))
                                .frame(width: 32, height: 32)
                            Image(systemName: selectedPrediction?.placeId == prediction.placeId ? "checkmark" : "mappin")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(selectedPrediction?.placeId == prediction.placeId
                                                 ? RoamColors.reviewSuccess
                                                 : RoamColors.reviewAccent)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(prediction.mainText)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(RoamColors.text)
                                .lineLimit(1)
                            if !prediction.secondaryText.isEmpty {
                                Text(prediction.secondaryText)
                                    .font(.system(size: 11))
                                    .foregroundStyle(RoamColors.textMuted)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        if selectedPrediction?.placeId == prediction.placeId {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(RoamColors.reviewSuccess)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                if index < min(autocompletePredictions.count, 5) - 1 {
                    Divider()
                        .padding(.leading, 56)
                }
            }
        }
        .background(RoamColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(RoamColors.reviewBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }

    // MARK: - Map section

    private var mapSection: some View {
        ZStack {
            LocationPickerMapView(
                coordinate: Binding(
                    get: { pinCoordinate ?? CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060) },
                    set: { newCoord in
                        pinCoordinate = newCoord
                        reverseGeocode(newCoord)
                    }
                ),
                fitToken: mapFitToken
            )
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(RoamColors.reviewBorder, lineWidth: 1)
            )

            // Centered pin overlay
            Image(systemName: "mappin")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color(UIColor(RoamColors.reviewAccent)))
                .shadow(color: .black.opacity(0.3), radius: 2, y: 2)
                .offset(y: -14)

            VStack {
                Spacer()
                Text("Move map to adjust pin")
                    .font(.system(size: 10))
                    .foregroundStyle(RoamColors.textMuted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Selected address card

    private func selectedAddressCard(_ detail: GooglePlaceDetail) -> some View {
        let displayAddress = reverseGeocodedAddress ?? detail.address
        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(RoamColors.reviewSuccess.opacity(0.1))
                    .frame(width: 28, height: 28)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(RoamColors.reviewSuccess)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(detail.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(RoamColors.text)
                if !displayAddress.isEmpty {
                    Text(formatDisplayAddress(displayAddress))
                        .font(.system(size: 11))
                        .foregroundStyle(RoamColors.textMuted)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(RoamColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(RoamColors.reviewBorder, lineWidth: 1)
        )
    }

    // MARK: - Confirm button

    private var confirmButton: some View {
        Button {
            confirmSelection()
        } label: {
            Text("Confirm location")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(selectedPlaceDetail != nil || pinCoordinate != nil
                            ? RoamColors.reviewAccent
                            : RoamColors.reviewBorder)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(selectedPlaceDetail == nil && pinCoordinate == nil)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(RoamColors.surface)
    }

    // MARK: - Helpers

    private func runAutocomplete(_ q: String) async {
        isSearching = true
        defer { isSearching = false }
        do {
            autocompletePredictions = try await GooglePlacesAutocomplete.autocomplete(query: q)
        } catch {
            autocompletePredictions = []
        }
    }

    private func selectPrediction(_ prediction: GooglePlacePrediction) async {
        selectedPrediction = prediction
        autocompletePredictions = []
        reverseGeocodedAddress = nil
        isFetchingDetail = true
        defer { isFetchingDetail = false }

        if let detail = try? await GooglePlacesAutocomplete.placeDetails(placeId: prediction.placeId) {
            selectedPlaceDetail = detail
            pinCoordinate = CLLocationCoordinate2D(latitude: detail.latitude, longitude: detail.longitude)
            mapFitToken += 1
        }
    }

    private func confirmSelection() {
        if let detail = selectedPlaceDetail {
            let lat = pinCoordinate?.latitude ?? detail.latitude
            let lng = pinCoordinate?.longitude ?? detail.longitude
            let address = reverseGeocodedAddress ?? detail.address
            onConfirm(PickedLocation(
                placeId: nil,
                name: detail.name,
                address: address,
                latitude: lat,
                longitude: lng
            ))
        } else if let coord = pinCoordinate {
            onConfirm(PickedLocation(
                placeId: nil,
                name: searchText,
                address: reverseGeocodedAddress ?? "",
                latitude: coord.latitude,
                longitude: coord.longitude
            ))
        }
        dismiss()
    }

    private func reverseGeocode(_ coord: CLLocationCoordinate2D) {
        geocodeTask?.cancel()
        geocodeTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let geocoder = CLGeocoder()
            let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            if let placemarks = try? await geocoder.reverseGeocodeLocation(location),
               let pm = placemarks.first {
                let parts = [
                    [pm.subThoroughfare, pm.thoroughfare].compactMap { $0 }.joined(separator: " "),
                    pm.locality,
                    pm.administrativeArea,
                    pm.country
                ].compactMap { $0?.isEmpty == true ? nil : $0 }
                let address = parts.joined(separator: ", ")
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    reverseGeocodedAddress = address.isEmpty ? nil : address
                }
            }
        }
    }

    /// Strips zip code from display address: "27 W 32nd St, New York, NY 10001, USA" → "27 W 32nd St, New York, NY, United States"
    private func formatDisplayAddress(_ raw: String) -> String {
        var parts = raw.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        parts = parts.map { part in
            let trimmed = part.replacingOccurrences(
                of: "\\s+\\d{5}(-\\d{4})?$",
                with: "",
                options: .regularExpression
            )
            return trimmed
        }
        if let last = parts.last, last == "USA" {
            parts[parts.count - 1] = "United States"
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Google Places Autocomplete (REST)

struct GooglePlacePrediction: Equatable {
    let placeId: String
    let mainText: String
    let secondaryText: String
    let fullDescription: String
}

struct GooglePlaceDetail {
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
}

enum GooglePlacesAutocomplete {
    private static let autocompleteEndpoint = "https://maps.googleapis.com/maps/api/place/autocomplete/json"
    private static let detailsEndpoint = "https://maps.googleapis.com/maps/api/place/details/json"

    // MARK: - Autocomplete

    static func autocomplete(query: String) async throws -> [GooglePlacePrediction] {
        guard let apiKey = GooglePlacePhotoService.mapsAPIKey() else { return [] }
        var components = URLComponents(string: autocompleteEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "input", value: query),
            URLQueryItem(name: "key", value: apiKey),
        ]
        guard let url = components.url else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(AutocompleteResponse.self, from: data)
        guard response.status == "OK" || response.status == "ZERO_RESULTS" else { return [] }
        return (response.predictions ?? []).map { p in
            GooglePlacePrediction(
                placeId: p.placeId,
                mainText: p.structuredFormatting?.mainText ?? p.description,
                secondaryText: p.structuredFormatting?.secondaryText ?? "",
                fullDescription: p.description
            )
        }
    }

    // MARK: - Place Details (lat/lng + formatted address)

    static func placeDetails(placeId: String) async throws -> GooglePlaceDetail? {
        guard let apiKey = GooglePlacePhotoService.mapsAPIKey() else { return nil }
        var components = URLComponents(string: detailsEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "place_id", value: placeId),
            URLQueryItem(name: "fields", value: "name,formatted_address,geometry"),
            URLQueryItem(name: "key", value: apiKey),
        ]
        guard let url = components.url else { return nil }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(PlaceDetailsResponse.self, from: data)
        guard response.status == "OK", let result = response.result else { return nil }
        let loc = result.geometry?.location
        return GooglePlaceDetail(
            name: result.name ?? "",
            address: result.formattedAddress ?? "",
            latitude: loc?.lat ?? 0,
            longitude: loc?.lng ?? 0
        )
    }

    // MARK: - Response types

    private struct AutocompleteResponse: Decodable {
        let predictions: [Prediction]?
        let status: String

        struct Prediction: Decodable {
            let placeId: String
            let description: String
            let structuredFormatting: StructuredFormatting?

            enum CodingKeys: String, CodingKey {
                case placeId = "place_id"
                case description
                case structuredFormatting = "structured_formatting"
            }
        }

        struct StructuredFormatting: Decodable {
            let mainText: String?
            let secondaryText: String?

            enum CodingKeys: String, CodingKey {
                case mainText = "main_text"
                case secondaryText = "secondary_text"
            }
        }
    }

    private struct PlaceDetailsResponse: Decodable {
        let result: ResultBody?
        let status: String

        struct ResultBody: Decodable {
            let name: String?
            let formattedAddress: String?
            let geometry: Geometry?

            enum CodingKeys: String, CodingKey {
                case name
                case formattedAddress = "formatted_address"
                case geometry
            }
        }

        struct Geometry: Decodable {
            let location: LatLng?
        }

        struct LatLng: Decodable {
            let lat: Double
            let lng: Double
        }
    }
}

// MARK: - Google Maps view (pin is a SwiftUI overlay; map pans under it)

struct LocationPickerMapView: UIViewRepresentable {
    @Binding var coordinate: CLLocationCoordinate2D
    var fitToken: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> GMSMapView {
        let camera = GMSCameraPosition.camera(withTarget: coordinate, zoom: 15)
        let mapView = GMSMapView(frame: .zero, camera: camera)
        mapView.delegate = context.coordinator
        mapView.isMyLocationEnabled = true
        mapView.overrideUserInterfaceStyle = .light
        mapView.settings.compassButton = false
        context.coordinator.mapView = mapView
        context.coordinator.lastFitToken = fitToken
        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.lastFitToken != fitToken {
            context.coordinator.lastFitToken = fitToken
            let camera = GMSCameraPosition.camera(withTarget: coordinate, zoom: 15)
            mapView.animate(to: camera)
        }
    }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: LocationPickerMapView
        weak var mapView: GMSMapView?
        var lastFitToken: Int?

        init(_ parent: LocationPickerMapView) { self.parent = parent }

        /// Called when the map stops moving — report center as the new coordinate.
        func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
            parent.coordinate = position.target
        }
    }
}
