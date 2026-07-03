import Foundation
import AppKit
import ScreenCaptureKit

final class HotbarStore: ObservableObject {
    static let shared = HotbarStore()

    @Published var slots: [Int: WindowInfo] = [:]
    @Published var windows: [WindowInfo] = []
    @Published var selectedIndex: Int = 0

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
        let fetched = WindowFetcher.fetchAllWindows()
        DispatchQueue.main.async {
            self.windows = fetched
            self.loadThumbnails()
        }
    }

    /// Capture window previews via ScreenCaptureKit (macOS 14+).
    /// Requires Screen Recording permission; silently keeps app icons otherwise.
    private func loadThumbnails() {
        guard #available(macOS 14.0, *) else { return }
        guard CGPreflightScreenCaptureAccess() else { return }

        Task { @MainActor in
            guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else {
                return
            }
            for windowInfo in self.windows where windowInfo.thumbnail == nil {
                guard let scWindow = content.windows.first(where: { $0.windowID == windowInfo.id }) else { continue }

                let maxWidth: CGFloat = 360
                let scale = min(1, maxWidth / max(scWindow.frame.width, 1))
                let config = SCStreamConfiguration()
                config.width = max(1, Int(scWindow.frame.width * scale))
                config.height = max(1, Int(scWindow.frame.height * scale))
                config.showsCursor = false
                let filter = SCContentFilter(desktopIndependentWindow: scWindow)

                guard let cgImage = try? await SCScreenshotManager.captureImage(
                    contentFilter: filter, configuration: config
                ) else { continue }

                // Windows list may have been refreshed meanwhile — match by id
                if let idx = self.windows.firstIndex(where: { $0.id == windowInfo.id }) {
                    self.windows[idx].thumbnail = NSImage(
                        cgImage: cgImage,
                        size: NSSize(width: cgImage.width, height: cgImage.height)
                    )
                }
            }
        }
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
