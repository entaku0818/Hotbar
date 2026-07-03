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

        let ownPID = ProcessInfo.processInfo.processIdentifier

        for info in windowList {
            guard
                let windowID = info[kCGWindowNumber] as? CGWindowID,
                let ownerPID = info[kCGWindowOwnerPID] as? pid_t,
                let layer = info[kCGWindowLayer] as? Int,
                layer == 0,
                ownerPID != ownPID
            else { continue }

            // NOTE: kCGWindowName requires Screen Recording permission and is
            // usually empty without it — never filter on the title. Filter by
            // window size instead to drop tiny helper/invisible windows.
            if let boundsDict = info[kCGWindowBounds] as? [String: CGFloat] {
                let width = boundsDict["Width"] ?? 0
                let height = boundsDict["Height"] ?? 0
                guard width >= 100, height >= 80 else { continue }
            }

            let ownerName = info[kCGWindowOwnerName] as? String ?? "Unknown"
            guard !ownerName.isEmpty,
                  ownerName != "Window Server",
                  ownerName != "Dock",
                  ownerName != "スクリーンショット",
                  ownerName != "Screenshot"
            else { continue }

            let rawTitle = info[kCGWindowName] as? String ?? ""
            let title = rawTitle.isEmpty ? ownerName : rawTitle

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
        NSLog("[Hotbar] activateWindow: pid=%d app=%@ title=%@", windowInfo.pid, windowInfo.appName, windowInfo.title)

        let apps = NSWorkspace.shared.runningApplications
        guard let app = apps.first(where: { $0.processIdentifier == windowInfo.pid }) else {
            NSLog("[Hotbar] activateWindow: app not found for pid=%d", windowInfo.pid)
            return
        }

        // Step 1: AX で特定ウィンドウを前面に
        let axApp = AXUIElementCreateApplication(windowInfo.pid)
        var windowsRef: CFTypeRef?
        let axResult = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
        NSLog("[Hotbar] AXCopyWindows result=%d", axResult.rawValue)

        if axResult == .success, let axWindows = windowsRef as? [AXUIElement] {
            NSLog("[Hotbar] AX windows count=%d", axWindows.count)
            var matched = false
            for axWindow in axWindows {
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
                let axTitle = titleRef as? String ?? ""
                NSLog("[Hotbar] AX window title='%@'", axTitle)
                if axTitle == windowInfo.title {
                    AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
                    AXUIElementSetAttributeValue(axWindow, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
                    matched = true
                    NSLog("[Hotbar] AX raise matched window")
                    break
                }
            }
            if !matched {
                // タイトルが変わっていても最初のウィンドウを前面に
                if let first = axWindows.first {
                    AXUIElementSetAttributeValue(first, kAXMainAttribute as CFString, kCFBooleanTrue)
                    AXUIElementSetAttributeValue(first, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
                    NSLog("[Hotbar] AX raise first window (title mismatch fallback)")
                }
            }
        }

        // Step 2: アプリを前面に
        AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, kCFBooleanTrue)

        // Step 3: NSRunningApplication でも activate（AX が効かないアプリ用）
        let activated = app.activate(options: [.activateIgnoringOtherApps])
        NSLog("[Hotbar] NSRunningApplication.activate result=%d", activated ? 1 : 0)

        // Step 4: AppleScript fallback
        if !activated {
            let src = "tell application \"\(windowInfo.appName)\" to activate"
            if let script = NSAppleScript(source: src) {
                var err: NSDictionary?
                script.executeAndReturnError(&err)
                if let err { NSLog("[Hotbar] AppleScript error: %@", err) }
            }
        }
    }
}
