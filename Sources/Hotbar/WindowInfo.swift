import AppKit
import CoreGraphics
import ScreenCaptureKit

struct WindowInfo: Identifiable, Equatable {
    let id: CGWindowID
    let title: String
    let appName: String
    let appBundleIdentifier: String?
    let pid: pid_t
    var thumbnail: NSImage?
    var appIcon: NSImage?

    static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Window fetching

final class WindowFetcher {
    static func fetchAllWindows() -> [WindowInfo] {
        var windows: [WindowInfo] = []

        let options = CGWindowListOption([.optionOnScreenOnly, .excludeDesktopElements])
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[CFString: Any]] else {
            return windows
        }

        let runningApps = NSWorkspace.shared.runningApplications
            .reduce(into: [pid_t: NSRunningApplication]()) { $0[$1.processIdentifier] = $1 }

        for info in windowList {
            guard
                let windowID = info[kCGWindowNumber] as? CGWindowID,
                let ownerPID = info[kCGWindowOwnerPID] as? pid_t,
                let layer = info[kCGWindowLayer] as? Int,
                layer == 0
            else { continue }

            let title = info[kCGWindowName] as? String ?? ""
            let ownerName = info[kCGWindowOwnerName] as? String ?? "Unknown"

            guard !ownerName.isEmpty,
                  ownerName != "Window Server",
                  ownerName != "Dock",
                  !title.isEmpty
            else { continue }

            let app = runningApps[ownerPID]
            let bundleID = app?.bundleIdentifier
            let appIcon = app?.icon

            windows.append(WindowInfo(
                id: windowID,
                title: title,
                appName: ownerName,
                appBundleIdentifier: bundleID,
                pid: ownerPID,
                thumbnail: nil,
                appIcon: appIcon
            ))
        }

        return windows
    }

    // ScreenCaptureKit でサムネイルを非同期取得（macOS 14.0+）
    @available(macOS 14.0, *)
    static func captureThumbnail(windowID: CGWindowID) async -> NSImage? {
        do {
            let content = try await SCShareableContent.current
            guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
                return nil
            }
            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let config = SCStreamConfiguration()
            config.width = 400
            config.height = 300
            config.scalesToFit = true
            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } catch {
            return nil
        }
    }

    static func activateWindow(_ windowInfo: WindowInfo) {
        let apps = NSWorkspace.shared.runningApplications
        guard let app = apps.first(where: { $0.processIdentifier == windowInfo.pid }) else { return }

        app.activate(options: [])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let axApp = AXUIElementCreateApplication(windowInfo.pid)
            var windowsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let axWindows = windowsRef as? [AXUIElement] else { return }

            for axWindow in axWindows {
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
                let axTitle = titleRef as? String ?? ""
                if axTitle == windowInfo.title {
                    AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
                    AXUIElementSetAttributeValue(axWindow, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
                    break
                }
            }
        }
    }
}
