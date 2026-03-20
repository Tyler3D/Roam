import Foundation

enum SharedStore {
    /// This must match the App Group ID you configure in Xcode (instructions below).
    static let appGroupID = "group.columbiastartupstudio.Roam"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func save(_ item: SharedItem) {
        var items = loadAll()
        items.insert(item, at: 0)
        if let data = try? JSONEncoder().encode(items) {
            defaults?.set(data, forKey: "sharedItems")
        }
    }

    static func loadAll() -> [SharedItem] {
        guard let data = defaults?.data(forKey: "sharedItems"),
              let items = try? JSONDecoder().decode([SharedItem].self, from: data) else {
            return []
        }
        return items
    }

    static func clearAll() {
        defaults?.removeObject(forKey: "sharedItems")
    }

    static func remove(id: UUID) {
        var items = loadAll()
        items.removeAll { $0.id == id }
        if let data = try? JSONEncoder().encode(items) {
            defaults?.set(data, forKey: "sharedItems")
        }
    }
}
