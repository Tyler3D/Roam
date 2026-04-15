import Foundation

enum DeepLinkDestination: Equatable {
    case reels
    case ideaDetail(ideaId: String)
    case map
    case profile
    case ideas
    case friends(prefilledUsername: String?)
}

@MainActor
@Observable
final class DeepLinkRouter {
    var pending: DeepLinkDestination?

    static func parse(userInfo: [AnyHashable: Any]?) -> DeepLinkDestination? {
        guard let info = userInfo, let type = info["type"] as? String else { return nil }

        switch type {
        case "reel_processed", "reel_needs_review":
            return .reels

        case "coincidence_match", "same_reel_saved", "trending_place", "collection_idea_added":
            if let ideaId = info["ideaId"] as? String {
                return .ideaDetail(ideaId: ideaId)
            }
            return .map

        case "friend_request", "friend_request_accepted":
            return .profile

        case "weekly_digest", "monthly_stats":
            return .ideas

        default:
            return .ideas
        }
    }
}
