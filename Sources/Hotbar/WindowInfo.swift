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
        // Identifiable supplies stable identity; equality must also reflect displayed content.
        lhs.id == rhs.id && lhs.pid == rhs.pid && lhs.title == rhs.title
            && lhs.appName == rhs.appName && lhs.appBundleIdentifier == rhs.appBundleIdentifier
            && lhs.thumbnail === rhs.thumbnail && lhs.appIcon === rhs.appIcon
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

    static func activateWindow(_ windowInfo: WindowInfo) {
        NSLog("[Hotbar] activateWindow: pid=%d app=%@ title=%@", windowInfo.pid, windowInfo.appName, windowInfo.title)

        guard let app = NSRunningApplication(processIdentifier: windowInfo.pid) else {
            NSLog("[Hotbar] activateWindow: app not found for pid=%d", windowInfo.pid)
            return
        }

        let axApp = AXUIElementCreateApplication(windowInfo.pid)
        let target = axWindow(for: windowInfo, in: axApp)
        if target == nil { NSLog("[Hotbar] activateWindow: no unique AX window match") }

        // Activate the app first. Apps such as Chrome bring their own key window forward on
        // activation, so the specific window must be raised *after* activation (and again once
        // the activation has settled) — otherwise same-app switching lands on the wrong window.
        if let target { raise(target, in: axApp) }
        let activated = app.activate(options: [.activateIgnoringOtherApps])
        AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        NSLog("[Hotbar] NSRunningApplication.activate result=%d", activated ? 1 : 0)
        if let target {
            raise(target, in: axApp)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { raise(target, in: axApp) }
        }

        if !activated {
            let src = "tell application \"\(windowInfo.appName)\" to activate"
            if let script = NSAppleScript(source: src) {
                var err: NSDictionary?
                script.executeAndReturnError(&err)
                if let err { NSLog("[Hotbar] AppleScript error: %@", err) }
            }
        }
    }

    private static func raise(_ window: AXUIElement, in app: AXUIElement) {
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, window)
    }

    /// Resolves the exact AX window for a CG window. Same-app windows often share titles
    /// (or have empty titles without Screen Recording), so titles are only a last resort.
    private static func axWindow(for info: WindowInfo, in axApp: AXUIElement) -> AXUIElement? {
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement], !axWindows.isEmpty else { return nil }

        let candidates = axWindows.map { window -> WindowCandidate in
            var windowID: CGWindowID = 0
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
            return WindowCandidate(
                windowID: _AXUIElementGetWindow(window, &windowID) == .success ? windowID : nil,
                frame: WindowArranger.frame(of: window),
                title: titleRef as? String
            )
        }
        let index = matchingWindowIndex(id: info.id, frame: currentFrame(of: info),
                                        title: info.title, candidates: candidates)
        return index.map { axWindows[$0] }
    }

    struct WindowCandidate: Equatable {
        let windowID: CGWindowID?
        let frame: CGRect?
        let title: String?
    }

    /// Match priority: window ID → unique frame → unique title. Returns nil instead of guessing.
    static func matchingWindowIndex(id: CGWindowID, frame: CGRect?, title: String,
                                    candidates: [WindowCandidate]) -> Int? {
        if let index = candidates.firstIndex(where: { $0.windowID == id }) { return index }
        if let frame, let index = WindowArranger.matchingIndex(frame: frame, candidates: candidates.map(\.frame)) {
            return index
        }
        let titled = candidates.indices.filter { candidates[$0].title == title }
        return titled.count == 1 ? titled.first : nil
    }

    private static func currentFrame(of info: WindowInfo) -> CGRect? {
        guard let records = CGWindowListCopyWindowInfo(.optionIncludingWindow, info.id) as? [[CFString: Any]],
              let record = records.first(where: { ($0[kCGWindowNumber] as? CGWindowID) == info.id }),
              record[kCGWindowOwnerPID] as? pid_t == info.pid,
              let bounds = record[kCGWindowBounds] as? [String: Any] else { return nil }
        return CGRect(dictionaryRepresentation: bounds as CFDictionary)
    }
}

/// Private but stable (used by most macOS window switchers): maps an AX window to its CGWindowID.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: inout CGWindowID) -> AXError
