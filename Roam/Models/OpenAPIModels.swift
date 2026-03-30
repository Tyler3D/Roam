import Foundation
@_exported import RoamOpenAPI

typealias RoamUser = Components.Schemas.UserRead
typealias Idea = Components.Schemas.IdeaRead
typealias IdeaPage = Components.Schemas.IdeaPageRead
typealias Plan = Components.Schemas.PlanRead
typealias PlanMemberRead = Components.Schemas.PlanMemberRead
typealias RoamNotification = Components.Schemas.NotificationRead
typealias IdeaStatus = Components.Schemas.IdeaStatus
typealias PlanStatus = Components.Schemas.PlanStatus
typealias MemberRole = Components.Schemas.MemberRole
typealias RsvpStatus = Components.Schemas.RsvpStatus
typealias NotificationType = Components.Schemas.NotificationType
typealias IdeaCreatePayload = Components.Schemas.IdeaCreate
typealias PipelineResult = Components.Schemas.PipelineResultRead

extension Components.Schemas.UserRead {
    var displayName: String {
        let f = firstName.trimmingCharacters(in: .whitespaces)
        let l = lastName.trimmingCharacters(in: .whitespaces)
        if f.isEmpty, l.isEmpty { return username ?? email ?? "Roam" }
        return [f, l].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

extension Components.Schemas.PlanRead {
    var resolvedMembers: [PlanMemberRead] {
        members ?? []
    }
}

extension Components.Schemas.NotificationRead {
    /// JSON key is `type`; generator uses `_type` (Swift keyword).
    var notificationType: NotificationType { _type }
}

extension Components.Schemas.IdeaRead: Identifiable {}

extension Components.Schemas.IdeaRead {
    /// Collection UUIDs from the API (personal default first when present).
    var linkedCollectionUUIDs: [UUID] {
        (collectionIds ?? []).compactMap { UUID(uuidString: $0.lowercased()) }
    }
}
extension Components.Schemas.PlanRead: Identifiable {}
extension Components.Schemas.NotificationRead: Identifiable {}
extension Components.Schemas.PlanMemberRead: Identifiable {}
