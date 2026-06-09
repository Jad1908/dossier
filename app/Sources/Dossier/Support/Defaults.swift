import Foundation

// Persisted preferences (DESKTOP_APP_SPEC §4), kept in UserDefaults. The
// settings UI binds most of these by their raw keys via @AppStorage; the keys
// below are the single source of those strings.
enum Defaults {
    enum Key {
        static let enginePath = "enginePathOverride"
        static let recents = "recentProjectPaths"
        static let appearance = "appearance"                 // system | light | dark
        static let reopenLastProject = "reopenLastProject"   // Bool
        static let defaultPreviewMode = "defaultPreviewMode" // outline | full
    }

    private static let enginePathKey = Key.enginePath
    private static let recentsKey = Key.recents
    private static let recentsLimit = 10

    /// Register the defaults for keys whose "unset" value is not the type's zero
    /// (e.g. reopen-on-launch defaults to true). Call once at launch.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.appearance: "system",
            Key.reopenLastProject: true,
            Key.defaultPreviewMode: "outline",
        ])
    }

    static var reopenLastProject: Bool {
        UserDefaults.standard.bool(forKey: Key.reopenLastProject)
    }

    static var defaultPreviewMode: String {
        UserDefaults.standard.string(forKey: Key.defaultPreviewMode) ?? "outline"
    }

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
