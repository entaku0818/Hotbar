import AppKit
import CoreGraphics

final class HotKeyManager {
    private weak var overlayController: OverlayWindowController?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    // Local monitor as safety net when Hotbar is active
    private var localMonitor: Any?

    init(overlayController: OverlayWindowController) {
        self.overlayController = overlayController
    }

    func start() {
        startCGEventTap()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let controller = self.overlayController, controller.isVisible else {
                return event
            }
            self.handleOverlayKey(keyCode: event.keyCode, flags: event.modifierFlags)
            return nil
        }
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        if let monitor = localMonitor { NSEvent.removeMonitor(monitor) }
        localMonitor = nil
    }

    // MARK: - CGEventTap

    private func startCGEventTap() {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

        let selfPtr = Unmanaged.passRetained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userInfo).takeUnretainedValue()
                return manager.handleCGEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: selfPtr
        ) else {
            // CGEventTap creation failed (no Accessibility permission yet)
            // Fall back to NSEvent global monitor
            startNSEventMonitor()
            return
        }

        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = src
    }

    private func handleCGEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passRetained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        let isOption  = flags.contains(.maskAlternate)
        let isCommand = flags.contains(.maskCommand)
        let isShift   = flags.contains(.maskShift)
        let isControl = flags.contains(.maskControl)
        let isSpace   = keyCode == 49

        // ⌥+Space: toggle overlay (no other modifiers)
        if type == .keyDown, isOption, isSpace, !isCommand, !isShift, !isControl {
            DispatchQueue.main.async { self.overlayController?.toggle() }
            return nil // consume — don't pass to other apps
        }

        // keyUp: cancel long-press
        if type == .keyUp {
            DispatchQueue.main.async { HoldKeyDetector.shared.cancel() }
            return Unmanaged.passRetained(event)
        }

        // Below: only active when overlay is visible
        guard overlayController?.isVisible == true else {
            return Unmanaged.passRetained(event)
        }

        // ESC
        if keyCode == 53 {
            DispatchQueue.main.async { self.overlayController?.hide() }
            return nil
        }

        // ⌘+1〜9 → slot jump
        if flags.contains(.maskCommand), !isOption, keyCode >= 18, keyCode <= 26 {
            // keyCodes 18-26 = 1-9 on main keyboard
            let digit = Int(keyCode) - 17
            DispatchQueue.main.async {
                self.overlayController?.hide()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    HotbarStore.shared.activateSlot(index: digit)
                }
            }
            return nil
        }

        // 数字長押し → スロット登録
        if !flags.contains(.maskCommand), keyCode >= 18, keyCode <= 26 {
            let digit = Int(keyCode) - 17
            DispatchQueue.main.async { HoldKeyDetector.shared.start(digit: digit) }
            return nil
        }

        return Unmanaged.passRetained(event)
    }

    // MARK: - NSEvent fallback (when CGEventTap unavailable)

    private var nsGlobalMonitor: Any?

    private func startNSEventMonitor() {
        nsGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return }
            if event.type == .keyUp { HoldKeyDetector.shared.cancel(); return }
            let isOption  = event.modifierFlags.contains(.option)
            let isCommand = event.modifierFlags.contains(.command)
            let isSpace   = event.keyCode == 49
            if isOption, isSpace, !isCommand {
                DispatchQueue.main.async { self.overlayController?.toggle() }
                return
            }
            guard self.overlayController?.isVisible == true else { return }
            DispatchQueue.main.async { self.handleOverlayKey(keyCode: event.keyCode, flags: event.modifierFlags) }
        }
    }

    // MARK: - Shared overlay key logic

    func handleOverlayKey(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        guard let controller = overlayController, controller.isVisible else { return }

        if keyCode == 53 { controller.hide(); return }

        if flags.contains(.option), keyCode == 49 { controller.toggle(); return }

        if flags.contains(.command), keyCode >= 18, keyCode <= 26 {
            let digit = Int(keyCode) - 17
            controller.hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                HotbarStore.shared.activateSlot(index: digit)
            }
            return
        }

        if !flags.contains(.command), keyCode >= 18, keyCode <= 26 {
            HoldKeyDetector.shared.start(digit: Int(keyCode) - 17)
        }
    }

    deinit { stop() }
}

// MARK: - Long-press detector

final class HoldKeyDetector {
    static let shared = HoldKeyDetector()

    private var timer: Timer?
    private(set) var currentDigit: Int?
    let holdDuration: TimeInterval
    private let store: HotbarStore

    convenience init() { self.init(holdDuration: 0.5, store: .shared) }

    init(holdDuration: TimeInterval, store: HotbarStore) {
        self.holdDuration = holdDuration
        self.store = store
    }

    func start(digit: Int) {
        if currentDigit == digit { return }
        cancel()
        currentDigit = digit
        timer = Timer.scheduledTimer(withTimeInterval: holdDuration, repeats: false) { [weak self] _ in
            self?.triggerRegister()
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        currentDigit = nil
    }

    func triggerRegister() {
        guard let digit = currentDigit else { return }
        guard store.windows.indices.contains(store.selectedIndex) else { cancel(); return }
        let window = store.windows[store.selectedIndex]
        store.assignSlot(index: digit, windowInfo: window)
        NotificationCenter.default.post(name: .hotbarSlotAssigned, object: digit)
        cancel()
    }
}

extension Notification.Name {
    static let hotbarSlotAssigned = Notification.Name("hotbarSlotAssigned")
}
