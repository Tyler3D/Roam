import Foundation

struct SharedItem: Codable, Identifiable {
    let id: UUID
    let url: String?
    let text: String?
    let dateShared: Date

    /// Raw type identifiers the share system gave us (e.g. "public.url", "public.plain-text").
    /// This is the "what did Instagram/TikTok actually hand over?" data.
    let attachmentTypeIdentifiers: [String]
}
