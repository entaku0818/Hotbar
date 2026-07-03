import Foundation
import AppKit

/// AltTab-inspired user settings, persisted in UserDefaults.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// Hold mode (AltTab-style): keep the modifier held, tap the key to
    /// cycle, release the modifier to activate the selected window.
    /// Toggle mode: press once to open, press again / ESC to close.
    @Published var holdMode: Bool {
        didSet { defaults.set(holdMode, forKey: Keys.holdMode) }
    }

    /// Thumbnail cell width in points (grid adapts around this).
    @Published var thumbnailSize: Double {
        didSet { defaults.set(thumbnailSize, forKey: Keys.thumbnailSize) }
    }

    @Published var showTitles: Bool {
        didSet { defaults.set(showTitles, forKey: Keys.showTitles) }
    }

    /// App names hidden from the window list.
    @Published var excludedApps: Set<String> {
        didSet { defaults.set(Array(excludedApps), forKey: Keys.excludedApps) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let holdMode = "holdMode"
        static let thumbnailSize = "thumbnailSize"
        static let showTitles = "showTitles"
        static let excludedApps = "excludedApps"
    }

    convenience init() {
        self.init(defaults: .standard)
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        self.holdMode = defaults.object(forKey: Keys.holdMode) as? Bool ?? true
        self.thumbnailSize = defaults.object(forKey: Keys.thumbnailSize) as? Double ?? 160
        self.showTitles = defaults.object(forKey: Keys.showTitles) as? Bool ?? true
        self.excludedApps = Set(defaults.stringArray(forKey: Keys.excludedApps) ?? [])
    }
}
