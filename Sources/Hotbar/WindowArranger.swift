import AppKit
import SwiftUI

enum WindowAction: String, CaseIterable {
    case left = "Left half"
    case right = "Right half"
    case maximize = "Maximize"
    case center = "Center"
    case nextScreen = "Next display"

    var symbol: String {
        switch self {
        case .left: return "rectangle.lefthalf.inset.filled"
        case .right: return "rectangle.righthalf.inset.filled"
        case .maximize: return "arrow.up.left.and.arrow.down.right"
        case .center: return "arrow.down.right.and.arrow.up.left"
        case .nextScreen: return "display.2"
        }
    }

    func frame(current: CGRect, visible: CGRect) -> CGRect {
        switch self {
        case .left:
            return CGRect(x: visible.minX, y: visible.minY, width: visible.width / 2, height: visible.height)
        case .right:
            return CGRect(x: visible.midX, y: visible.minY, width: visible.width / 2, height: visible.height)
        case .maximize: return visible
        case .center, .nextScreen:
            let size = CGSize(width: min(current.width, visible.width), height: min(current.height, visible.height))
            return CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                          width: size.width, height: size.height)
        }
    }
}

struct WindowActionBar: View {
    @EnvironmentObject var store: HotbarStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                ForEach(WindowAction.allCases, id: \.self) { action in
                    Button {
                        store.performWindowAction(action)
                    } label: {
                        Label(LocalizedStringKey(action.rawValue), systemImage: action.symbol)
                    }
                    .disabled(!store.windows.indices.contains(store.selectedIndex)
                              || (action == .nextScreen && NSScreen.screens.count < 2))
                }
            }
            .controlSize(.small)
            if let message = store.windowActionMessage {
                Text(LocalizedStringKey(message))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Arrange the selected window. Maximize keeps the Dock and menu bar visible.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Uses a fresh Core Graphics frame and a unique AX frame match; never falls back to another window.
enum WindowArranger {
    enum Failure: LocalizedError {
        case permission, unavailable, ambiguous, unsupported, rejected, noDisplay

        var errorDescription: String? {
            switch self {
            case .permission: return "Enable Accessibility in System Settings to arrange windows."
            case .unavailable: return "This window is no longer available. Reopen the switcher."
            case .ambiguous: return "Cannot identify this window uniquely. Move overlapping windows apart and try again."
            case .unsupported: return "This app does not allow this window to be moved or resized."
            case .rejected: return "The app could not apply the requested layout. Its minimum size or full-screen mode may prevent it."
            case .noDisplay: return "No other display is available."
            }
        }
    }

    static func perform(_ action: WindowAction, on info: WindowInfo) throws {
        guard AXIsProcessTrusted() else { throw Failure.permission }
        let (window, current) = try resolve(info)
        var positionWritable = DarwinBoolean(false)
        var sizeWritable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &positionWritable)
        AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &sizeWritable)
        guard positionWritable.boolValue, sizeWritable.boolValue else { throw Failure.unsupported }
        let screens = NSScreen.screens
        guard let primary = screens.first else { throw Failure.noDisplay }
        let visibleFrames = screens.map { axFrame($0.visibleFrame, primaryHeight: primary.frame.maxY) }
        let screenIndex = screenIndex(for: current, frames: visibleFrames)
        if action == .nextScreen, screens.count < 2 { throw Failure.noDisplay }
        let destination = action == .nextScreen ? (screenIndex + 1) % screens.count : screenIndex
        let target = action.frame(current: current, visible: visibleFrames[destination])
        var point = target.origin
        var size = target.size
        guard let position = AXValueCreate(.cgPoint, &point), let dimensions = AXValueCreate(.cgSize, &size) else {
            throw Failure.unsupported
        }
        // Shrink before moving, then retry size after moving across displays.
        let initialSize = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions)
        let moved = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        let resized = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions)
        guard initialSize == .success || resized == .success, moved == .success,
              let actual = frame(of: window), framesMatch(actual, target, tolerance: 3) else {
            throw Failure.rejected
        }
    }

    static func axFrame(_ frame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    static func screenIndex(for window: CGRect, frames: [CGRect]) -> Int {
        frames.indices.max { left, right in
            let leftIntersection = window.intersection(frames[left])
            let rightIntersection = window.intersection(frames[right])
            let leftArea = leftIntersection.isNull ? 0 : leftIntersection.width * leftIntersection.height
            let rightArea = rightIntersection.isNull ? 0 : rightIntersection.width * rightIntersection.height
            return leftArea < rightArea
        } ?? 0
    }

    static func framesMatch(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 1) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
    }

    static func matchingIndex(frame target: CGRect, candidates: [CGRect?]) -> Int? {
        let matches = candidates.indices.filter { index in
            candidates[index].map { framesMatch($0, target) } ?? false
        }
        return matches.count == 1 ? matches.first : nil
    }

    private static func resolve(_ info: WindowInfo) throws -> (AXUIElement, CGRect) {
        guard let records = CGWindowListCopyWindowInfo(.optionIncludingWindow, info.id) as? [[CFString: Any]],
              let record = records.first(where: { ($0[kCGWindowNumber] as? CGWindowID) == info.id }),
              record[kCGWindowOwnerPID] as? pid_t == info.pid,
              let bounds = record[kCGWindowBounds] as? [String: Any],
              let target = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { throw Failure.unavailable }
        let app = AXUIElementCreateApplication(info.pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { throw Failure.unavailable }
        guard let index = matchingIndex(frame: target, candidates: windows.map { frame(of: $0) }) else {
            throw Failure.ambiguous
        }
        return (windows[index], target)
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, let sizeRef,
              CFGetTypeID(positionRef) == AXValueGetTypeID(), CFGetTypeID(sizeRef) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(positionRef, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeDowncast(sizeRef, to: AXValue.self), .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
}
