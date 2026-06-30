import Foundation
import AppKit

final class HotbarStore: ObservableObject {
    static let shared = HotbarStore()

    @Published var slots: [Int: WindowInfo] = [:]
    @Published var windows: [WindowInfo] = []
    @Published var selectedIndex: Int = 0

    private let slotsKey = "hotbarSlots"

    private init() {
        loadSlots()
    }

    func refreshWindows() {
        let fetched = WindowFetcher.fetchAllWindows()
        DispatchQueue.main.async {
            self.windows = fetched
        }
    }

    func assignSlot(index: Int, windowInfo: WindowInfo) {
        slots[index] = windowInfo
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

    private func saveSlots() {
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
        UserDefaults.standard.set(encoded, forKey: slotsKey)
    }

    private func loadSlots() {
        guard let encoded = UserDefaults.standard.dictionary(forKey: slotsKey) as? [String: [String: String]] else {
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
