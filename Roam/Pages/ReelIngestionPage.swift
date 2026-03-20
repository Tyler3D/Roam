import SwiftUI

/// Shared links queue from the app extension; [`POST /api/ingest`](backend/app/api/ingest.py) for pipeline handoff.
struct ReelIngestionPage: View {
    @Environment(\.apiClient) private var apiClient
    @Environment(\.scenePhase) private var scenePhase
    @State private var items: [SharedItem] = []
    @State private var ingestError: String?
    @State private var ingestingId: UUID?

    var body: some View {
        Group {
            if items.isEmpty {
                RoamEmptyState(
                    icon: "⇪",
                    title: "no shared links",
                    subtitle: "Share a link from Safari, Instagram, or TikTok to see it here."
                )
                .padding(.top, 24)
            } else {
                List {
                    if let ingestError {
                        Text(ingestError)
                            .font(RoamFont.mono(10))
                            .foregroundStyle(RoamColors.error)
                    }
                    ForEach(items) { item in
                        NavigationLink {
                            ItemDetailView(item: item)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.url ?? item.text ?? "Unknown")
                                    .font(RoamFont.mono(12))
                                    .lineLimit(2)
                                Text(item.dateShared, style: .relative)
                                    .font(RoamFont.mono(9))
                                    .foregroundStyle(RoamColors.textMuted)
                            }
                            .padding(.vertical, 4)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if reelURL(for: item) != nil {
                                Button {
                                    Task { await ingest(item) }
                                } label: {
                                    Label("Ingest", systemImage: "arrow.up.circle.fill")
                                }
                                .tint(RoamColors.loganDeep)
                            }
                            Button(role: .destructive) {
                                remove(item)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button("Send to Roam (ingest)") {
                                Task { await ingest(item) }
                            }
                            .disabled(ingestingId != nil || reelURL(for: item) == nil)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("shared")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !items.isEmpty {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button("Clear all local", role: .destructive) {
                            SharedStore.clearAll()
                            items = []
                        }
                    } label: {
                        Text("⋯")
                            .font(RoamFont.mono(16))
                    }
                }
            }
        }
        .onAppear { reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reload() }
        }
    }

    private func reload() {
        items = SharedStore.loadAll()
    }

    private func remove(_ item: SharedItem) {
        SharedStore.remove(id: item.id)
        reload()
    }

    private func reelURL(for item: SharedItem) -> String? {
        if let u = item.url, !u.isEmpty { return u }
        if let t = item.text, let url = URL(string: t), url.scheme == "http" || url.scheme == "https" {
            return t
        }
        return nil
    }

    private func ingest(_ item: SharedItem) async {
        guard let url = reelURL(for: item) else {
            ingestError = "No URL to ingest"
            return
        }
        ingestError = nil
        ingestingId = item.id
        defer { ingestingId = nil }
        do {
            _ = try await apiClient.submitIngest(reelUrl: url, shareText: item.text)
            SharedStore.remove(id: item.id)
            reload()
        } catch {
            ingestError = error.localizedDescription
        }
    }
}
