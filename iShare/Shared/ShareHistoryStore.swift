import Foundation

struct SharedFile: Codable, Identifiable {
    let id: String
    let filename: String
    let url: String
    let expiresAt: String
    let sharedAt: Date
}

/// Stores recent shares in the App Group's UserDefaults suite so both
/// the main app and the share extension read/write the same list.
enum ShareHistoryStore {
    private static let key = "recentShares"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: RelayConfig.appGroupID) ?? .standard
    }

    static func add(_ file: SharedFile) {
        var items = all()
        items.insert(file, at: 0)
        if items.count > 25 { items = Array(items.prefix(25)) }
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: key)
        }
    }

    static func all() -> [SharedFile] {
        guard let data = defaults.data(forKey: key),
              let items = try? JSONDecoder().decode([SharedFile].self, from: data) else {
            return []
        }
        return items
    }
}
