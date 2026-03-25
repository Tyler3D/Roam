import Foundation
import Observation
import SwiftUI

private struct RoamStoresKey: EnvironmentKey {
    static var defaultValue: RoamStores {
        RoamStores(api: APIClient.previewForSwiftUIPreviews)
    }
}

extension EnvironmentValues {
    var roamStores: RoamStores {
        get { self[RoamStoresKey.self] }
        set { self[RoamStoresKey.self] = newValue }
    }
}

@MainActor
@Observable
final class RoamStores {
    let ideas: IdeasQueryStore
    let reels: ReelsQueryStore
    let plans: PlansQueryStore
    let notifications: NotificationsQueryStore
    let user: UserQueryStore
    let mapCollections: MapCollectionsQueryStore

    init(api: APIClient) {
        ideas = IdeasQueryStore(api: api)
        reels = ReelsQueryStore(api: api)
        plans = PlansQueryStore(api: api)
        notifications = NotificationsQueryStore(api: api)
        user = UserQueryStore(api: api)
        mapCollections = MapCollectionsQueryStore(api: api)
    }

    func refreshAll() async {
        async let ideasTask = ideas.refresh()
        async let reelsTask = reels.refresh()
        async let plansTask = plans.refresh()
        async let notificationsTask = notifications.refresh()
        async let userTask = user.refresh()
        async let collectionsTask = mapCollections.refreshCollections()
        async let pinsTask = mapCollections.refreshPins()
        _ = await (
            ideasTask,
            reelsTask,
            plansTask,
            notificationsTask,
            userTask,
            collectionsTask,
            pinsTask
        )
    }
}
