import Foundation

// Persisted preferences (DESKTOP_APP_SPEC §4): the dossier binary path override
// and the recent-project list, kept in UserDefaults.
enum Defaults {
    private static let enginePathKey = "enginePathOverride"
    private static let recentsKey = "recentProjectPaths"
    private static let recentsLimit = 10

    static var enginePathOverride: String? {
        get {
            let v = UserDefaults.standard.string(forKey: enginePathKey)
            return (v?.isEmpty ?? true) ? nil : v
        }
        set { UserDefaults.standard.set(newValue, forKey: enginePathKey) }
    }

    static var recentProjectPaths: [String] {
        get { UserDefaults.standard.stringArray(forKey: recentsKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: recentsKey) }
    }

    static func noteRecentProject(_ url: URL) {
        var list = recentProjectPaths.filter { $0 != url.path }
        list.insert(url.path, at: 0)
        recentProjectPaths = Array(list.prefix(recentsLimit))
    }
}
