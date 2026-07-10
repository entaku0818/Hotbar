import AppKit
import CoreGraphics

final class HotKeyManager {
    private weak var overlayController: OverlayWindowController?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    // Local monitor as safety net when Hotbar is active
    private var localMonitor: Any?
    private var nsGlobalMonitor: Any?

    private var hotkey = HotkeyPreference.load()

    var isTapActive: Bool { eventTap != nil }

    init(overlayController: OverlayWindowController) {
        self.overlayController = overlayController
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotkeyChanged),
            name: .hotkeyPreferenceChanged,
            object: nil
        )
    }

    @objc private func hotkeyChanged() {
        hotkey = HotkeyPreference.load()
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

    /// Retry CGEventTap creation — call after accessibility permission is granted.
    func restartTapIfNeeded() {
        guard eventTap == nil, AXIsProcessTrusted() else { return }
        if let monitor = nsGlobalMonitor {
            NSEvent.removeMonitor(monitor)
            nsGlobalMonitor = nil
        }
        startCGEventTap()
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
        if let monitor = nsGlobalMonitor { NSEvent.removeMonitor(monitor) }
        nsGlobalMonitor = nil
    }

    // MARK: - CGEventTap

    private func startCGEventTap() {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

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
            NSLog("[Hotbar] CGEventTap creation FAILED (accessibility not granted?) — falling back to NSEvent monitor")
            startNSEventMonitor()
            return
        }

        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = src
        NSLog("[Hotbar] CGEventTap active")
    }

    private func handleCGEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if handleTapDisabledIfNeeded(type: type) {
            return Unmanaged.passRetained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Hold mode: releasing the hotkey's modifier activates the selection
        if type == .flagsChanged {
            handleFlagsChanged(flags: flags)
            return Unmanaged.passRetained(event)
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passRetained(event)
        }

        // Hotkey (user-configurable, default ⌥Tab). Shift reverses direction.
        if type == .keyDown, hotkey.matchesIgnoringShift(keyCode: keyCode, cgFlags: flags) {
            handleHotkeyPress(reverse: flags.contains(.maskShift) && !hotkey.shift)
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

        return handleOverlayVisibleKey(keyCode: keyCode, flags: flags, event: event)
    }

    /// Re-enables the tap if the system disabled it (timeout / user input flood).
    /// Returns true when the event was fully handled here.
    private func handleTapDisabledIfNeeded(type: CGEventType) -> Bool {
        guard type == .tapDisabledByTimeout || type == .tapDisabledByUserInput else { return false }
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
        return true
    }

    private func handleFlagsChanged(flags: CGEventFlags) {
        guard AppSettings.shared.holdMode,
              overlayController?.isVisible == true,
              hotkey.hasModifier,
              !hotkey.modifiersStillHeld(cgFlags: flags) else { return }
        DispatchQueue.main.async { HotbarStore.shared.activateSelectedWindow() }
    }

    private func handleHotkeyPress(reverse: Bool) {
        DispatchQueue.main.async {
            guard let controller = self.overlayController else { return }
            if controller.isVisible {
                if AppSettings.shared.holdMode {
                    HotbarStore.shared.cycleSelection(forward: !reverse)
                } else {
                    controller.toggle()
                }
            } else {
                controller.show()
            }
        }
    }

    /// Handles keys that only act while the overlay is visible: ESC, arrows,
    /// Return, and the digit-slot keys (⌘+digit jump / hold-digit register).
    private func handleOverlayVisibleKey(keyCode: Int64, flags: CGEventFlags, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch keyCode {
        case 53: // ESC
            DispatchQueue.main.async { self.overlayController?.hide() }
            return nil
        case 123, 126: // ← ↑
            DispatchQueue.main.async { HotbarStore.shared.cycleSelection(forward: false) }
            return nil
        case 124, 125: // → ↓
            DispatchQueue.main.async { HotbarStore.shared.cycleSelection(forward: true) }
            return nil
        case 36: // Return
            DispatchQueue.main.async { HotbarStore.shared.activateSelectedWindow() }
            return nil
        default:
            return handleDigitSlotKey(keyCode: keyCode, flags: flags, event: event)
        }
    }

    /// keyCodes 18-26 = 1-9 on the main keyboard. ⌘+digit jumps to a slot;
    /// digit alone (held) registers the current selection into that slot.
    private func handleDigitSlotKey(keyCode: Int64, flags: CGEventFlags, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard keyCode >= 18, keyCode <= 26 else {
            return Unmanaged.passRetained(event)
        }
        let digit = Int(keyCode) - 17
        if flags.contains(.maskCommand) {
            DispatchQueue.main.async {
                self.overlayController?.hide()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    HotbarStore.shared.activateSlot(index: digit)
                }
            }
        } else {
            DispatchQueue.main.async { HoldKeyDetector.shared.start(digit: digit) }
        }
        return nil
    }

    // MARK: - NSEvent fallback (when CGEventTap unavailable)

    private func startNSEventMonitor() {
        nsGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self else { return }
            if event.type == .flagsChanged {
                if AppSettings.shared.holdMode,
                   self.overlayController?.isVisible == true,
                   self.hotkey.hasModifier,
                   !self.hotkey.modifiersStillHeld(cgFlags: Self.cgFlags(from: event.modifierFlags)) {
                    DispatchQueue.main.async { HotbarStore.shared.activateSelectedWindow() }
                }
                return
            }
            if event.type == .keyUp { HoldKeyDetector.shared.cancel(); return }
            if self.hotkey.matchesIgnoringShift(keyCode: Int64(event.keyCode), cgFlags: Self.cgFlags(from: event.modifierFlags)) {
                let reverse = event.modifierFlags.contains(.shift) && !self.hotkey.shift
                DispatchQueue.main.async {
                    guard let controller = self.overlayController else { return }
                    if controller.isVisible {
                        if AppSettings.shared.holdMode {
                            HotbarStore.shared.cycleSelection(forward: !reverse)
                        } else {
                            controller.toggle()
                        }
                    } else {
                        controller.show()
                    }
                }
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

        if hotkey.matchesIgnoringShift(keyCode: Int64(keyCode), cgFlags: Self.cgFlags(from: flags)) {
            if AppSettings.shared.holdMode {
                HotbarStore.shared.cycleSelection(forward: !flags.contains(.shift) || hotkey.shift)
            } else {
                controller.toggle()
            }
            return
        }

        if keyCode == 123 || keyCode == 126 { HotbarStore.shared.cycleSelection(forward: false); return }
        if keyCode == 124 || keyCode == 125 { HotbarStore.shared.cycleSelection(forward: true); return }
        if keyCode == 36 { HotbarStore.shared.activateSelectedWindow(); return }

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

    private static func cgFlags(from flags: NSEvent.ModifierFlags) -> CGEventFlags {
        var cg = CGEventFlags()
        if flags.contains(.option) { cg.insert(.maskAlternate) }
        if flags.contains(.command) { cg.insert(.maskCommand) }
        if flags.contains(.shift) { cg.insert(.maskShift) }
        if flags.contains(.control) { cg.insert(.maskControl) }
        return cg
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stop()
    }
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
