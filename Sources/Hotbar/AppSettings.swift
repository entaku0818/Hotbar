import Foundation
import AppKit
import SwiftUI

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

    @Published var favoriteApps: Set<String> {
        didSet { defaults.set(Array(favoriteApps), forKey: "favoriteApps") }
    }

    @Published var windowOrder: WindowOrder {
        didSet { defaults.set(windowOrder.rawValue, forKey: "windowOrder") }
    }

    @Published var overlayPosition: OverlayPosition {
        didSet { defaults.set(overlayPosition.rawValue, forKey: "overlayPosition") }
    }

    @Published var accent: HotbarAccent {
        didSet { defaults.set(accent.rawValue, forKey: "hotbarAccent") }
    }

    @Published var showSlotNames: Bool {
        didSet { defaults.set(showSlotNames, forKey: "showSlotNames") }
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
        favoriteApps = Set(defaults.stringArray(forKey: "favoriteApps") ?? [])
        windowOrder = WindowOrder(rawValue: defaults.string(forKey: "windowOrder") ?? "") ?? .recent
        overlayPosition = OverlayPosition(rawValue: defaults.string(forKey: "overlayPosition") ?? "") ?? .center
        accent = HotbarAccent(rawValue: defaults.string(forKey: "hotbarAccent") ?? "") ?? .system
        showSlotNames = defaults.object(forKey: "showSlotNames") as? Bool ?? true
        self.holdMode = defaults.object(forKey: Keys.holdMode) as? Bool ?? true
        self.thumbnailSize = defaults.object(forKey: Keys.thumbnailSize) as? Double ?? 160
        self.showTitles = defaults.object(forKey: Keys.showTitles) as? Bool ?? true
        self.excludedApps = Set(defaults.stringArray(forKey: Keys.excludedApps) ?? [])
    }
}

enum WindowOrder: String, CaseIterable {
    case recent = "Recent first"
    case appName = "App name"
    case title = "Window title"
}

enum OverlayPosition: String, CaseIterable {
    case center = "Center"
    case top = "Top"
    case bottom = "Bottom"

    func origin(in screen: CGRect, panelSize: CGSize) -> CGPoint {
        let margin: CGFloat = 16
        let vertical: CGFloat
        switch self {
        case .center: vertical = screen.midY - panelSize.height / 2
        case .top: vertical = screen.maxY - panelSize.height - margin
        case .bottom: vertical = screen.minY + margin
        }
        return CGPoint(
            x: max(screen.minX, screen.midX - panelSize.width / 2),
            y: max(screen.minY, min(vertical, screen.maxY - panelSize.height))
        )
    }
}

enum HotbarAccent: String, CaseIterable {
    case system = "System"
    case blue = "Blue"
    case purple = "Purple"
    case orange = "Orange"
    case green = "Green"

    var color: Color {
        switch self {
        case .system: return .accentColor
        case .blue: return .blue
        case .purple: return .purple
        case .orange: return .orange
        case .green: return .green
        }
    }
}
