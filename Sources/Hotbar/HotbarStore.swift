import Foundation
import AppKit
import ScreenCaptureKit

final class HotbarStore: ObservableObject {
    static let shared = HotbarStore()

    @Published var slots: [Int: WindowInfo] = [:]
    @Published var windowActionMessage: String?
    @Published var windows: [WindowInfo] = []
    @Published var selectedIndex: Int = 0

    private var thumbnailTask: Task<Void, Never>?

    private let slotsKey = "hotbarSlots"
    private let defaults: UserDefaults

    private init() {
        self.defaults = .standard
        loadSlots()
    }

    // Testable initializer with custom UserDefaults suite
    init(defaults: UserDefaults) {
        self.defaults = defaults
        loadSlots()
    }

    func refreshWindows() {
        let settings = AppSettings.shared
        let allWindows = WindowFetcher.fetchAllWindows()
        let visible = Self.applyExclusions(allWindows, excluded: settings.excludedApps)
        let previousID = visible.dropFirst().first?.id
        let fetched = Self.orderWindows(visible, favorites: settings.favoriteApps, order: settings.windowOrder)
        windowActionMessage = nil
        // Preserve previews synchronously so opening the panel never flashes back to icons.
        windows = Self.reusingThumbnails(in: fetched, from: windows, allowed: CGPreflightScreenCaptureAccess())
        selectedIndex = settings.holdMode
            ? (fetched.firstIndex(where: { $0.id == previousID }) ?? 0) : 0
        loadThumbnails()
    }

    static func reusingThumbnails(in fetched: [WindowInfo], from previous: [WindowInfo],
                                  allowed: Bool) -> [WindowInfo] {
        let cached = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        return fetched.map { window in
            var updated = window
            // Window IDs may be reused by a different process. Never reuse its pixels.
            if allowed, let old = cached[window.id], old.pid == window.pid {
                updated.thumbnail = old.thumbnail
            }
            return updated
        }
    }

    static func applyExclusions(_ windows: [WindowInfo], excluded: Set<String>) -> [WindowInfo] {
        guard !excluded.isEmpty else { return windows }
        return windows.filter { !excluded.contains($0.appName) }
    }

    static func orderWindows(_ windows: [WindowInfo], favorites: Set<String>, order: WindowOrder) -> [WindowInfo] {
        windows.enumerated().sorted { lhs, rhs in
            let leftFavorite = favorites.contains(lhs.element.appName)
            let rightFavorite = favorites.contains(rhs.element.appName)
            if leftFavorite != rightFavorite { return leftFavorite }
            let comparison: ComparisonResult
            switch order {
            case .recent: return lhs.offset < rhs.offset
            case .appName:
                comparison = lhs.element.appName.localizedStandardCompare(rhs.element.appName)
            case .title:
                comparison = lhs.element.title.localizedStandardCompare(rhs.element.title)
            }
            return comparison == .orderedSame ? lhs.offset < rhs.offset : comparison == .orderedAscending
        }.map(\.element)
    }

    func performWindowAction(_ action: WindowAction) {
        guard windows.indices.contains(selectedIndex) else { return }
        do {
            try WindowArranger.perform(action, on: windows[selectedIndex])
            windowActionMessage = nil
        } catch {
            windowActionMessage = error.localizedDescription
        }
    }

    func cycleSelection(forward: Bool) {
        guard !windows.isEmpty else { return }
        let count = windows.count
        selectedIndex = ((selectedIndex + (forward ? 1 : -1)) % count + count) % count
    }

    func activateSelectedWindow() {
        guard windows.indices.contains(selectedIndex) else {
            NotificationCenter.default.post(name: .hideOverlay, object: nil)
            return
        }
        let window = windows[selectedIndex]
        NotificationCenter.default.post(name: .hideOverlay, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            self.activateWindow(window)
        }
    }

    func cancelThumbnailLoading() {
        thumbnailTask?.cancel()
        thumbnailTask = nil
    }

    /// Keep cached previews visible while refreshing, with at most three captures in flight.
    private func loadThumbnails() {
        cancelThumbnailLoading()
        guard #available(macOS 14.0, *), CGPreflightScreenCaptureAccess() else { return }
        let requested = windows
        let selectedID = windows.indices.contains(selectedIndex) ? windows[selectedIndex].id : nil

        thumbnailTask = Task { @MainActor [weak self] in
            let started = Date()
            guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
                  !Task.isCancelled else { return }
            let available = Dictionary(content.windows.map { ($0.windowID, $0) },
                                       uniquingKeysWith: { first, _ in first })
            let ordered = Self.thumbnailOrder(requested, selectedID: selectedID)
            let targets = ordered.compactMap { info -> (WindowInfo, SCWindow)? in
                guard let window = available[info.id],
                      window.owningApplication?.processID == info.pid else { return nil }
                return (info, window)
            }
            await withTaskGroup(of: (CGWindowID, pid_t, CGImage?).self) { group in
                var next = 0
                var completed = 0
                for _ in 0..<min(3, targets.count) {
                    let target = targets[next]
                    next += 1
                    group.addTask { (target.0.id, target.0.pid, await Self.captureThumbnail(target.1)) }
                }
                for await (windowID, pid, image) in group {
                    guard !Task.isCancelled else {
                        group.cancelAll()
                        return
                    }
                    if let image, let self,
                       let index = self.windows.firstIndex(where: { $0.id == windowID && $0.pid == pid }) {
                        self.windows[index].thumbnail = NSImage(
                            cgImage: image, size: NSSize(width: image.width, height: image.height)
                        )
                        completed += 1
                        if completed == 1 {
                            NSLog("[Hotbar] First refreshed preview: %.0f ms", Date().timeIntervalSince(started) * 1000)
                        }
                    }
                    if next < targets.count {
                        let target = targets[next]
                        next += 1
                        group.addTask { (target.0.id, target.0.pid, await Self.captureThumbnail(target.1)) }
                    }
                }
                NSLog("[Hotbar] Refreshed %d previews in %.0f ms", completed, Date().timeIntervalSince(started) * 1000)
            }
        }
    }

    static func thumbnailOrder(_ windows: [WindowInfo], selectedID: CGWindowID?) -> [WindowInfo] {
        windows.enumerated().sorted { lhs, rhs in
            let left = lhs.element
            let right = rhs.element
            if (left.id == selectedID) != (right.id == selectedID) { return left.id == selectedID }
            if (left.thumbnail == nil) != (right.thumbnail == nil) { return left.thumbnail == nil }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    @available(macOS 14.0, *)
    private static func captureThumbnail(_ window: SCWindow) async -> CGImage? {
        guard !Task.isCancelled else { return nil }
        let scale = min(1, 360 / max(window.frame.width, window.frame.height, 1))
        let config = SCStreamConfiguration()
        config.width = max(1, Int(window.frame.width * scale))
        config.height = max(1, Int(window.frame.height * scale))
        config.showsCursor = false
        return try? await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config
        )
    }

    func assignSlot(index: Int, windowInfo: WindowInfo) {
        guard index >= 1 && index <= 9 else { return }
        slots[index] = windowInfo
        saveSlots()
    }

    func clearSlot(index: Int) {
        slots.removeValue(forKey: index)
        saveSlots()
    }

    func activateSlot(index: Int) {
        guard let windowInfo = slots[index] else { return }
        WindowFetcher.activateWindow(windowInfo)
    }

    func activateWindow(_ windowInfo: WindowInfo) {
        WindowFetcher.activateWindow(windowInfo)
    }

    // MARK: - Persistence

    func saveSlots() {
        var encoded: [String: [String: String]] = [:]
        for (key, value) in slots {
            encoded["\(key)"] = [
                "id": "\(value.id)",
                "title": value.title,
                "appName": value.appName,
                "bundleID": value.appBundleIdentifier ?? "",
                "pid": "\(value.pid)"
            ]
        }
        defaults.set(encoded, forKey: slotsKey)
    }

    func loadSlots() {
        guard let encoded = defaults.dictionary(forKey: slotsKey) as? [String: [String: String]] else {
            return
        }
        var restored: [Int: WindowInfo] = [:]
        for (keyStr, dict) in encoded {
            guard
                let key = Int(keyStr),
                let idStr = dict["id"],
                let windowID = CGWindowID(idStr),
                let title = dict["title"],
                let appName = dict["appName"],
                let pidStr = dict["pid"],
                let pid = pid_t(pidStr)
            else { continue }

            let bundleID = dict["bundleID"]?.isEmpty == false ? dict["bundleID"] : nil
            let apps = NSWorkspace.shared.runningApplications
            let app = apps.first(where: { $0.processIdentifier == pid })

            restored[key] = WindowInfo(
                id: windowID,
                title: title,
                appName: appName,
                appBundleIdentifier: bundleID,
                pid: pid,
                thumbnail: nil,
                appIcon: app?.icon
            )
        }
        slots = restored
    }
}
