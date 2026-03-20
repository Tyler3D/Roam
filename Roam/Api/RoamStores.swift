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

    init(api: APIClient) {
        ideas = IdeasQueryStore(api: api)
        reels = ReelsQueryStore(api: api)
        plans = PlansQueryStore(api: api)
        notifications = NotificationsQueryStore(api: api)
        user = UserQueryStore(api: api)
    }

    func refreshAll() async {
        await ideas.refresh()
        await reels.refresh()
        await plans.refresh()
        await notifications.refresh()
        await user.refresh()
    }
}
