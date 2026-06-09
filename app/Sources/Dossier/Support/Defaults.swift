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
        static let zoomLevel = "zoomLevel"                   // Double (UI scale)
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
            Key.zoomLevel: 1.0,
        ])
    }

    /// UI scale for the whole window. Bounded so the layout never collapses or
    /// runs off the screen; 1.0 is the designed size.
    static let zoomRange: ClosedRange<Double> = 0.7...2.0
    static let zoomStep: Double = 0.1

    static var zoomLevel: Double {
        get { UserDefaults.standard.double(forKey: Key.zoomLevel) }
        set { UserDefaults.standard.set(newValue, forKey: Key.zoomLevel) }
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

extension Comparable {
    /// Pin a value into a closed range.
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
