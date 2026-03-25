import CoreLocation
import MapKit
import SwiftUI
import UIKit

/// Collection map: light chrome over **Google Maps** (`GMSMapView`) with saved-place pins.
struct CollectionMapExplorerView: View {
    @Environment(\.roamStores) private var stores
    @StateObject private var locationAuth = MapLocationAuthorizer()

    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 40.73, longitude: -73.99),
        span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
    )
    @State private var mapFitToken = 0
    @State private var categoryFilter: MapPlaceCategoryFilter = .all
    @State private var sheetExpanded = false
    @State private var selectedPin: APIClient.CollectionMapPinDTO?
    @State private var showDetail = false

    private var mc: MapCollectionsQueryStore { stores.mapCollections }

    private var pinsWithCoords: [(APIClient.CollectionMapPinDTO, CLLocationCoordinate2D)] {
        mc.mapPins.compactMap { pin -> (APIClient.CollectionMapPinDTO, CLLocationCoordinate2D)? in
            guard let lat = pin.placeLatitude, let lng = pin.placeLongitude else { return nil }
            return (pin, CLLocationCoordinate2D(latitude: lat, longitude: lng))
        }
    }

    private var filteredPins: [(APIClient.CollectionMapPinDTO, CLLocationCoordinate2D)] {
        pinsWithCoords.filter { categoryFilter.matches($0.0) }
    }

    private var filterSignature: String {
        let ids = mc.mapPins.map(\.id.uuidString).sorted().joined(separator: ",")
        let sel: String = {
            switch mc.selection {
            case .everything: return "e"
            case .mySaves: return "m"
            case .sharedCollection(let id): return id.uuidString
            }
        }()
        return "\(ids)|\(sel)|\(categoryFilter.rawValue)"
    }

    var body: some View {
        VStack(spacing: 0) {
            collectionChipBar
            mapStack
        }
        .background(RoamMapChrome.bg)
        .onChange(of: filterSignature) { _, _ in
            fitCamera(to: filteredPins.map(\.1))
        }
        .onAppear {
            locationAuth.requestWhenInUseIfNeeded()
            fitCamera(to: filteredPins.map(\.1))
        }
        // Note: sheetExpanded changes update mapInsets reactively via sheetCardHeight
        // in mapStack, so no manual camera re-fit is needed here.
    }

    // MARK: - Collection chips

    private var collectionChipBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                collectionChip(
                    title: "Everything",
                    selected: mc.selection == .everything,
                    count: mc.selection == .everything ? filteredPins.count : nil,
                    memberDots: { EmptyView() }
                ) {
                    Task { await mc.setSelection(.everything) }
                }

                collectionChip(
                    title: personalName,
                    selected: mc.selection == .mySaves,
                    count: mc.selection == .mySaves ? filteredPins.count : nil,
                    memberDots: { Circle().fill(RoamMapChrome.youTeal).frame(width: 7, height: 7) }
                ) {
                    Task { await mc.setSelection(.mySaves) }
                }

                ForEach(mc.sharedCollections) { c in
                    collectionChip(
                        title: c.name,
                        selected: mc.selection == .sharedCollection(c.id),
                        count: mc.selection == .sharedCollection(c.id) ? filteredPins.count : nil,
                        memberDots: { memberDotsView(for: c) }
                    ) {
                        Task { await mc.setSelection(.sharedCollection(c.id)) }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 12)
        }
    }

    private var personalName: String {
        mc.collections.first { $0.isPersonalDefault }?.name ?? "My saves"
    }

    private func collectionChip<Dots: View>(
        title: String,
        selected: Bool,
        count: Int?,
        @ViewBuilder memberDots: () -> Dots,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                memberDots()
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if let count {
                    Text("\(count)")
                        .font(RoamFont.mono(11, weight: .medium))
                        .foregroundStyle(selected ? Color.white.opacity(0.7) : RoamMapChrome.textMuted)
                }
            }
            .foregroundStyle(selected ? Color.white : RoamMapChrome.textMuted)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(selected ? RoamMapChrome.accent : RoamMapChrome.surface)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(selected ? RoamMapChrome.accent : RoamMapChrome.border, lineWidth: selected ? 1.5 : 1)
            )
            .shadow(color: .black.opacity(selected ? 0.12 : 0.06), radius: selected ? 8 : 3, x: 0, y: selected ? 2 : 1)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func memberDotsView(for c: APIClient.CollectionReadDTO) -> some View {
        let previews = Array((c.memberPreview ?? []).prefix(3))
        if previews.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 2) {
                ForEach(Array(previews.enumerated()), id: \.offset) { _, m in
                    Circle()
                        .fill(MapPinPalette.color(forIndex: abs(m.userId.hashValue % 8)))
                        .frame(width: 7, height: 7)
                }
            }
        }
    }

    // MARK: - Map + overlays

    private var mapStack: some View {
        GeometryReader { geo in
            let expandedSheetH = max(geo.size.height * 0.42, 200)
            let sheetCardHeight = sheetExpanded ? expandedSheetH : collapsedSheetHeight
            let mapInsets = UIEdgeInsets(
                top: mapTopInsetForCategoryPills,
                left: 6,
                bottom: sheetCardHeight + 6,
                right: 6
            )

            ZStack(alignment: .top) {
                if mc.isLoadingPins && mc.mapPins.isEmpty {
                    ProgressView("loading pins…")
                        .tint(RoamMapChrome.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(RoamMapChrome.bg)
                } else {
                    ZStack(alignment: .center) {
                        RoamGoogleMapView(
                            region: $mapRegion,
                            fitToken: mapFitToken,
                            pins: filteredPins,
                            selectedPinId: selectedPin?.id,
                            mapInsets: mapInsets,
                            onSelectPin: { pin in
                                selectedPin = pin
                                showDetail = true
                            },
                            onUserRegionChange: { mapRegion = $0 }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if !mc.isLoadingPins && filteredPins.isEmpty {
                            emptyState
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(RoamMapChrome.bg.opacity(0.72))
                        }
                    }
                }

                if !(mc.isLoadingPins && mc.mapPins.isEmpty) {
                    categoryPills
                        .padding(.top, 10)
                }

                if !legendEntries.isEmpty && !filteredPins.isEmpty {
                    personLegend
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(.trailing, 12)
                        .padding(.bottom, sheetCardHeight + 12)
                }

                bottomSheet(availableHeight: geo.size.height, expandedSheetHeight: expandedSheetH)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

                if showDetail, let pin = selectedPin {
                    mapPlaceDetailOverlay(pin: pin)
                }
            }
            .clipShape(Rectangle())
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("◎")
                .font(.system(size: 36))
                .foregroundStyle(RoamMapChrome.textMuted)
            Text("no pins here")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(RoamMapChrome.text)
            Text(
                mc.selection == .everything
                    ? "Save reels with places or add ideas with a location."
                    : "Nothing in this collection has coordinates yet."
            )
            .font(.system(size: 13))
            .foregroundStyle(RoamMapChrome.textMuted)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Category pills

    /// Space reserved above the map for the floating category chip row (padding + row).
    private var mapTopInsetForCategoryPills: CGFloat { 50 }

    private var categoryPills: some View {
        GeometryReader { g in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    Spacer(minLength: 0)
                    HStack(spacing: 5) {
                        ForEach(MapPlaceCategoryFilter.allCases) { cat in
                            Button {
                                categoryFilter = cat
                            } label: {
                                Text(cat.rawValue)
                                    .font(.system(size: 11, weight: categoryFilter == cat ? .semibold : .medium))
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 5)
                                    .foregroundStyle(categoryFilter == cat ? RoamMapChrome.accent : RoamMapChrome.textMuted)
                                    .background(categoryFilter == cat ? RoamMapChrome.accentGlow : RoamMapChrome.glass)
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule()
                                            .stroke(categoryFilter == cat ? RoamMapChrome.accent : RoamMapChrome.border.opacity(0.9), lineWidth: 1)
                                    )
                                    .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(minWidth: g.size.width)
            }
        }
        .frame(height: 36)
    }

    // MARK: - Legend

    private struct LegendRow: Identifiable {
        let id: String
        let label: String
        let color: Color
    }

    private var legendEntries: [LegendRow] {
        switch mc.selection {
        case .everything:
            var rows: [String: LegendRow] = [:]
            for (pin, _) in filteredPins {
                let name = pin.addedByDisplayName
                if rows[name] == nil {
                    rows[name] = LegendRow(id: name, label: name, color: MapPinPalette.color(forIndex: pin.colorIndex))
                }
            }
            return rows.values.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        case .mySaves:
            return [LegendRow(id: "you", label: "You", color: RoamMapChrome.youTeal)]
        case .sharedCollection(let id):
            guard let coll = mc.collections.first(where: { $0.id == id }) else { return [] }
            let previews = coll.memberPreview ?? []
            if previews.isEmpty { return [] }
            return previews.map { m in
                let name = [m.firstName, m.lastName].compactMap { $0 }.joined(separator: " ")
                let label = name.isEmpty ? "Member" : name
                let idx = abs(m.userId.hashValue % 8)
                return LegendRow(id: m.userId.uuidString, label: label, color: MapPinPalette.color(forIndex: idx))
            }
        }
    }

    private var personLegend: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(legendEntries) { row in
                HStack(spacing: 6) {
                    Circle()
                        .fill(row.color)
                        .frame(width: 7, height: 7)
                    Text(row.label)
                        .font(.system(size: 11))
                        .foregroundStyle(RoamMapChrome.textMuted)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .background(RoamMapChrome.glass)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(RoamMapChrome.borderLight, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    }

    // MARK: - Bottom sheet

    private let collapsedSheetHeight: CGFloat = 148
    /// Chevron + title / count row — must match layout below so list peek height is correct.
    private let sheetChromeHeaderHeight: CGFloat = 78

    private func bottomSheet(availableHeight: CGFloat, expandedSheetHeight: CGFloat) -> some View {
        let expandedH = expandedSheetHeight
        let collapsedH = collapsedSheetHeight
        let listPeekHeight = max(0, collapsedH - sheetChromeHeaderHeight)
        let expandedListHeight = max(0, expandedH - sheetChromeHeaderHeight)

        return VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                    sheetExpanded.toggle()
                }
            } label: {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Image(systemName: sheetExpanded ? "chevron.down" : "chevron.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(RoamMapChrome.textMuted)
                        Spacer()
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                    HStack(alignment: .firstTextBaseline) {
                        Text(sheetTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(RoamMapChrome.text)
                        Spacer()
                        Text("\(filteredPins.count) spots")
                            .font(RoamFont.mono(11, weight: .medium))
                            .foregroundStyle(RoamMapChrome.textMuted)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 10)
                }
            }
            .buttonStyle(.plain)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredPins.map(\.0), id: \.id) { pin in
                        mapSheetRow(pin: pin)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .frame(maxHeight: sheetExpanded ? expandedListHeight : listPeekHeight)
        }
        .frame(height: sheetExpanded ? expandedH : collapsedH, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(RoamMapChrome.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(RoamMapChrome.borderLight, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: -4)
    }

    private var sheetTitle: String {
        switch mc.selection {
        case .everything: return "All places"
        case .mySaves: return personalName
        case .sharedCollection(let id):
            return mc.collections.first { $0.id == id }?.name ?? "Collection"
        }
    }

    private func mapSheetRow(pin: APIClient.CollectionMapPinDTO) -> some View {
        Button {
            selectedPin = pin
            showDetail = true
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Circle()
                    .fill(MapPinPalette.color(forIndex: pin.colorIndex))
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pin.pinTitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(RoamMapChrome.text)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if let cat = pin.category?.trimmingCharacters(in: .whitespacesAndNewlines), !cat.isEmpty {
                            Text(cat.uppercased())
                                .font(RoamFont.mono(9, weight: .medium))
                                .foregroundStyle(RoamMapChrome.textMuted)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(RoamMapChrome.bg)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        if let addr = pin.placeAddress?.trimmingCharacters(in: .whitespacesAndNewlines), !addr.isEmpty {
                            Text(addr)
                                .font(.system(size: 11))
                                .foregroundStyle(RoamMapChrome.textMuted)
                                .lineLimit(1)
                        }
                    }
                    let note = pin.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !note.isEmpty {
                        Text(note)
                            .font(.system(size: 11))
                            .italic()
                            .foregroundStyle(RoamMapChrome.textMuted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(RoamMapChrome.textMuted)
            }
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(RoamMapChrome.border.opacity(0.45))
                    .frame(height: 1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail overlay

    private func mapPlaceDetailOverlay(pin: APIClient.CollectionMapPinDTO) -> some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.22)) {
                        showDetail = false
                        selectedPin = nil
                    }
                }

            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(RoamMapChrome.border)
                    .frame(width: 36, height: 4)
                    .padding(.top, 10)

                HStack(alignment: .top) {
                    Text(pin.pinTitle)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(RoamMapChrome.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        withAnimation(.easeOut(duration: 0.22)) {
                            showDetail = false
                            selectedPin = nil
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(RoamMapChrome.textMuted)
                            .frame(width: 30, height: 30)
                            .background(RoamMapChrome.bg)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(RoamMapChrome.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 16)

                if let addr = pin.placeAddress?.trimmingCharacters(in: .whitespacesAndNewlines), !addr.isEmpty {
                    Text(addr)
                        .font(.system(size: 13))
                        .foregroundStyle(RoamMapChrome.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }

                HStack(spacing: 6) {
                    if let cat = pin.category?.trimmingCharacters(in: .whitespacesAndNewlines), !cat.isEmpty {
                        Text(cat.uppercased())
                            .font(RoamFont.mono(10, weight: .medium))
                            .foregroundStyle(RoamMapChrome.textMuted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(RoamMapChrome.bg)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(RoamMapChrome.border, lineWidth: 1))
                    }
                    Text("saved")
                        .font(RoamFont.mono(10, weight: .medium))
                        .foregroundStyle(RoamMapChrome.textMuted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(RoamMapChrome.bg)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(RoamMapChrome.border, lineWidth: 1))
                }
                .padding(.top, 14)
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Circle()
                        .fill(MapPinPalette.color(forIndex: pin.colorIndex))
                        .frame(width: 24, height: 24)
                    HStack(spacing: 0) {
                        Text("Added by ")
                            .foregroundStyle(RoamMapChrome.textMuted)
                        Text(pin.addedByDisplayName)
                            .fontWeight(.medium)
                            .foregroundStyle(RoamMapChrome.text)
                        Text(" · \(pin.createdAt.formatted(date: .abbreviated, time: .omitted))")
                            .foregroundStyle(RoamMapChrome.textMuted)
                    }
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 12)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(RoamMapChrome.border)
                        .frame(height: 1)
                }
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(RoamMapChrome.border)
                        .frame(height: 1)
                }
                .padding(.top, 14)

                let note = pin.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                if !note.isEmpty {
                    Text(note)
                        .font(.system(size: 13))
                        .italic()
                        .foregroundStyle(RoamMapChrome.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(RoamMapChrome.bg)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(.top, 14)
                }

                HStack(spacing: 8) {
                    if let lat = pin.placeLatitude, let lng = pin.placeLongitude {
                        let q = pin.pinTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        if let url = URL(string: "http://maps.apple.com/?ll=\(lat),\(lng)&q=\(q)") {
                            Link(destination: url) {
                                Text("Open in Maps")
                                    .font(.system(size: 13, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(RoamMapChrome.bg)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(RoamMapChrome.border, lineWidth: 1.5))
                                    .foregroundStyle(RoamMapChrome.text)
                            }
                        }
                    }
                    NavigationLink {
                        IdeaDetailPage(ideaId: pin.id.uuidString.lowercased())
                    } label: {
                        Text("Plan this →")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoamMapChrome.accent)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .shadow(color: RoamMapChrome.accent.opacity(0.25), radius: 8, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .padding(.horizontal, 20)
            .background(RoamMapChrome.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.1), radius: 30, x: 0, y: -8)
            .padding(.top, 40)
        }
        .transition(.opacity)
        .zIndex(20)
    }

    // MARK: - Camera

    private func fitCamera(to coordinates: [CLLocationCoordinate2D]) {
        guard !coordinates.isEmpty else { return }
        if coordinates.count == 1 {
            let c = coordinates[0]
            mapRegion = MKCoordinateRegion(center: c, span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06))
        } else {
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
                latitudeDelta: max((maxLat - minLat) * 1.45, 0.04),
                longitudeDelta: max((maxLon - minLon) * 1.45, 0.04)
            )
            mapRegion = MKCoordinateRegion(center: center, span: span)
        }
        mapFitToken += 1
    }
}
