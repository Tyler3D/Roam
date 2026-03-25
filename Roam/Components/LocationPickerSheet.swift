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

/// A bottom-sheet style view for searching places (via backend) and fine-tuning
/// location with a draggable Google Maps pin.
struct LocationPickerSheet: View {
    var initialQuery: String
    var initialCoordinate: CLLocationCoordinate2D?
    var onConfirm: (PickedLocation) -> Void

    @Environment(\.apiClient) private var apiClient
    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String = ""
    @State private var searchResults: [APIClient.PlaceSearchRowDTO] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    @State private var selectedPlace: APIClient.PlaceSearchRowDTO?
    @State private var pinCoordinate: CLLocationCoordinate2D?
    @State private var mapFitToken = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                ScrollView {
                    VStack(spacing: 12) {
                        if !searchResults.isEmpty {
                            autocompleteList
                        }
                        mapSection
                        if let place = selectedPlace {
                            selectedAddressCard(place)
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
            if let coord = initialCoordinate {
                pinCoordinate = coord
            }
            if !initialQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Task { await runSearch(initialQuery) }
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
                        searchResults = []
                        return
                    }
                    searchTask = Task {
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        guard !Task.isCancelled else { return }
                        await runSearch(q)
                    }
                }
            if isSearching {
                ProgressView()
                    .controlSize(.small)
            }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchResults = []
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
            ForEach(Array(searchResults.prefix(5).enumerated()), id: \.element.id) { index, row in
                Button {
                    selectPlace(row)
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selectedPlace?.id == row.id
                                      ? RoamColors.reviewSuccess.opacity(0.12)
                                      : RoamColors.reviewAccent.opacity(0.08))
                                .frame(width: 32, height: 32)
                            Image(systemName: selectedPlace?.id == row.id ? "checkmark" : "mappin")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(selectedPlace?.id == row.id
                                                 ? RoamColors.reviewSuccess
                                                 : RoamColors.reviewAccent)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(RoamColors.text)
                                .lineLimit(1)
                            if let addr = row.address, !addr.isEmpty {
                                Text(addr)
                                    .font(.system(size: 11))
                                    .foregroundStyle(RoamColors.textMuted)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        if selectedPlace?.id == row.id {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(RoamColors.reviewSuccess)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                if index < min(searchResults.count, 5) - 1 {
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
        ZStack(alignment: .bottom) {
            LocationPickerMapView(
                coordinate: Binding(
                    get: { pinCoordinate ?? CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060) },
                    set: { pinCoordinate = $0 }
                ),
                fitToken: mapFitToken
            )
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(RoamColors.reviewBorder, lineWidth: 1)
            )

            Text("Drag pin to adjust")
                .font(.system(size: 10))
                .foregroundStyle(RoamColors.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .padding(.bottom, 8)
        }
    }

    // MARK: - Selected address card

    private func selectedAddressCard(_ place: APIClient.PlaceSearchRowDTO) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(RoamColors.reviewSuccess.opacity(0.1))
                    .frame(width: 28, height: 28)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(RoamColors.reviewSuccess)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(place.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(RoamColors.text)
                if let addr = place.address, !addr.isEmpty {
                    Text(formatDisplayAddress(addr))
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
                .background(selectedPlace != nil || pinCoordinate != nil
                            ? RoamColors.reviewAccent
                            : RoamColors.reviewBorder)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(selectedPlace == nil && pinCoordinate == nil)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(RoamColors.surface)
    }

    // MARK: - Helpers

    private func runSearch(_ q: String) async {
        isSearching = true
        defer { isSearching = false }
        do {
            searchResults = try await apiClient.searchPlacesList(query: q, limit: 5)
        } catch {
            searchResults = []
        }
    }

    private func selectPlace(_ row: APIClient.PlaceSearchRowDTO) {
        selectedPlace = row
        if let lat = row.latitude, let lng = row.longitude {
            pinCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            mapFitToken += 1
        }
    }

    private func confirmSelection() {
        if let place = selectedPlace {
            let lat = pinCoordinate?.latitude ?? place.latitude ?? 0
            let lng = pinCoordinate?.longitude ?? place.longitude ?? 0
            onConfirm(PickedLocation(
                placeId: place.id,
                name: place.name,
                address: place.address ?? "",
                latitude: lat,
                longitude: lng
            ))
        } else if let coord = pinCoordinate {
            onConfirm(PickedLocation(
                placeId: nil,
                name: searchText,
                address: "",
                latitude: coord.latitude,
                longitude: coord.longitude
            ))
        }
        dismiss()
    }

    /// Strips zip code from display address: "27 W 32nd St, New York, NY 10001, USA" → "27 W 32nd St, New York, NY, United States"
    private func formatDisplayAddress(_ raw: String) -> String {
        var parts = raw.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        // Remove zip codes from state parts like "NY 10001"
        parts = parts.map { part in
            let trimmed = part.replacingOccurrences(
                of: "\\s+\\d{5}(-\\d{4})?$",
                with: "",
                options: .regularExpression
            )
            return trimmed
        }
        // Replace "USA" with "United States" for readability
        if let last = parts.last, last == "USA" {
            parts[parts.count - 1] = "United States"
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Google Maps view with draggable pin

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

        let marker = GMSMarker(position: coordinate)
        marker.isDraggable = true
        marker.icon = GMSMarker.markerImage(with: UIColor(RoamColors.reviewAccent))
        marker.map = mapView
        context.coordinator.marker = marker

        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.lastFitToken != fitToken {
            context.coordinator.lastFitToken = fitToken
            let camera = GMSCameraPosition.camera(withTarget: coordinate, zoom: 15)
            mapView.animate(to: camera)
            context.coordinator.marker?.position = coordinate
        }
    }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: LocationPickerMapView
        weak var mapView: GMSMapView?
        var marker: GMSMarker?
        var lastFitToken: Int?

        init(_ parent: LocationPickerMapView) { self.parent = parent }

        func mapView(_ mapView: GMSMapView, didEndDragging marker: GMSMarker) {
            parent.coordinate = marker.position
        }

        func mapView(_ mapView: GMSMapView, didLongPressAt coordinate: CLLocationCoordinate2D) {
            marker?.position = coordinate
            parent.coordinate = coordinate
        }
    }
}
