import MapKit
import SwiftUI

struct MapPage: View {
    @Environment(\.roamStores) private var stores
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedPin: APIClient.CollectionMapPinDTO?

    var body: some View {
        VStack(spacing: 0) {
            chipBar
            mapArea
        }
        .navigationTitle("map")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedPin) { pin in
            MapPinCalloutSheet(pin: pin)
        }
        .task {
            await stores.mapCollections.refreshCollections()
            await stores.mapCollections.refreshPins()
        }
    }

    private var chipBar: some View {
        let mc = stores.mapCollections
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "everything", selected: mc.selection == .everything) {
                    Task { await mc.setSelection(.everything) }
                }
                chip(title: "my saves", selected: mc.selection == .mySaves) {
                    Task { await mc.setSelection(.mySaves) }
                }
                ForEach(mc.sharedCollections) { c in
                    chip(
                        title: c.name,
                        selected: mc.selection == .sharedCollection(c.id)
                    ) {
                        Task { await mc.setSelection(.sharedCollection(c.id)) }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(RoamColors.surface.opacity(0.95))
    }

    private func chip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(RoamFont.mono(10, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(selected ? RoamColors.loganDeep.opacity(0.2) : RoamColors.lavender.opacity(0.5))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(selected ? RoamColors.loganDeep : RoamColors.logan.opacity(0.25), lineWidth: selected ? 1.5 : 1)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var mapArea: some View {
        let mc = stores.mapCollections
        let pins = mc.mapPins.compactMap { pin -> (APIClient.CollectionMapPinDTO, CLLocationCoordinate2D)? in
            guard let lat = pin.placeLatitude, let lng = pin.placeLongitude else { return nil }
            return (pin, CLLocationCoordinate2D(latitude: lat, longitude: lng))
        }

        ZStack {
            if mc.isLoadingPins && pins.isEmpty {
                ProgressView("loading pins…")
                    .tint(RoamColors.loganDeep)
            } else if pins.isEmpty {
                RoamEmptyState(
                    icon: "◎",
                    title: "no pins here",
                    subtitle: mc.selection == .everything
                        ? "save reels with places or add ideas with a location"
                        : "nothing in this collection has coordinates yet"
                )
                .padding(.top, 40)
            } else {
                Map(position: $position) {
                    ForEach(pins, id: \.0.id) { pin, coord in
                        Annotation(pin.pinTitle, coordinate: coord) {
                            Button {
                                selectedPin = pin
                            } label: {
                                Circle()
                                    .fill(MapPinPalette.color(forIndex: pin.colorIndex))
                                    .frame(width: 14, height: 14)
                                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: mc.mapPins.map(\.id)) { _, _ in
            fitCamera(to: pins.map(\.1))
        }
    }

    private func fitCamera(to coordinates: [CLLocationCoordinate2D]) {
        guard !coordinates.isEmpty else { return }
        if coordinates.count == 1 {
            let c = coordinates[0]
            position = .region(MKCoordinateRegion(center: c, span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)))
            return
        }
        var minLat = coordinates[0].latitude
        var maxLat = minLat
        var minLon = coordinates[0].longitude
        var maxLon = minLon
        for c in coordinates.dropFirst() {
            minLat = min(minLat, c.latitude)
            maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude)
            maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.05),
            longitudeDelta: max((maxLon - minLon) * 1.4, 0.05)
        )
        position = .region(MKCoordinateRegion(center: center, span: span))
    }
}

private struct MapPinCalloutSheet: View {
    let pin: APIClient.CollectionMapPinDTO
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(pin.pinTitle)
                        .font(RoamFont.mono(14, weight: .medium))
                        .foregroundStyle(RoamColors.loganDark)
                    if let addr = pin.placeAddress?.trimmingCharacters(in: .whitespacesAndNewlines), !addr.isEmpty {
                        Text(addr)
                            .font(RoamFont.mono(11))
                            .foregroundStyle(RoamColors.textMid)
                    }
                    if let cat = pin.category?.trimmingCharacters(in: .whitespacesAndNewlines), !cat.isEmpty {
                        Text(cat)
                            .font(RoamFont.mono(9))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(RoamColors.lavender)
                            .clipShape(Capsule())
                    }
                    Text("added by \(pin.addedByDisplayName) · \(pin.createdAt.formatted(.relative(presentation: .named)))")
                        .font(RoamFont.mono(10))
                        .foregroundStyle(RoamColors.textMuted)
                    let note = pin.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !note.isEmpty {
                        Text(note)
                            .font(RoamFont.mono(11))
                            .foregroundStyle(RoamColors.text)
                    }
                    if let lat = pin.placeLatitude, let lng = pin.placeLongitude {
                        let q = pin.pinTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        if let url = URL(string: "http://maps.apple.com/?ll=\(lat),\(lng)&q=\(q)") {
                            Link(destination: url) {
                                Text("open in maps")
                                    .font(RoamFont.mono(11, weight: .medium))
                            }
                            .tint(RoamColors.loganDeep)
                        }
                    }
                    Button {
                        // placeholder — plan flow
                    } label: {
                        Text("plan this")
                            .font(RoamFont.mono(11, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .tint(RoamColors.loganDeep)
                    .disabled(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .navigationTitle("place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
