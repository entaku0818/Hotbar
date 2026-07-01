import AppKit

final class HotKeyManager {
    private weak var overlayController: OverlayWindowController?
    private var globalMonitor: Any?
    // Local monitor is kept only as a safety net; real work happens in global monitor
    private var localMonitor: Any?

    init(overlayController: OverlayWindowController) {
        self.overlayController = overlayController
    }

    func start() {
        // Global monitor handles ALL key events — including overlay interactions.
        // nonactivatingPanel means Hotbar is never the active app, so a local
        // monitor receives nothing while the overlay is visible.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            self?.handleGlobalKey(event)
        }

        // Local monitor: fallback for when Hotbar itself happens to be active
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let controller = self.overlayController, controller.isVisible else {
                return event
            }
            self.handleOverlayKey(event)
            return nil // consume
        }
    }

    func stop() {
        if let monitor = globalMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localMonitor  { NSEvent.removeMonitor(monitor) }
    }

    // MARK: - Global handler (fires for all apps)

    private func handleGlobalKey(_ event: NSEvent) {
        guard event.type == .keyDown else {
            // keyUp: cancel long-press
            if event.type == .keyUp { HoldKeyDetector.shared.cancel() }
            return
        }

        guard let controller = overlayController else { return }

        // ⌥+Space: toggle overlay
        if event.modifierFlags.contains(.option),
           !event.modifierFlags.contains(.command),
           !event.modifierFlags.contains(.shift),
           !event.modifierFlags.contains(.control),
           event.keyCode == 49 {
            DispatchQueue.main.async { controller.toggle() }
            return
        }

        guard controller.isVisible else { return }

        DispatchQueue.main.async { self.handleOverlayKey(event) }
    }

    // MARK: - Overlay-visible key handling

    private func handleOverlayKey(_ event: NSEvent) {
        guard let controller = overlayController, controller.isVisible else { return }

        // ESC → close
        if event.keyCode == 53 {
            controller.hide()
            return
        }

        // ⌥+Space → toggle
        if event.modifierFlags.contains(.option), event.keyCode == 49 {
            controller.toggle()
            return
        }

        // ⌘+1〜9 → jump to slot
        if event.modifierFlags.contains(.command),
           let char = event.charactersIgnoringModifiers,
           let digit = Int(char), digit >= 1, digit <= 9 {
            controller.hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                HotbarStore.shared.activateSlot(index: digit)
            }
            return
        }

        // 数字キー長押し → スロット登録
        if !event.modifierFlags.contains(.command),
           let char = event.charactersIgnoringModifiers,
           let digit = Int(char), digit >= 1, digit <= 9 {
            HoldKeyDetector.shared.start(digit: digit)
            return
        }
    }

    deinit { stop() }
}

// MARK: - Long-press detector for slot registration

final class HoldKeyDetector {
    static let shared = HoldKeyDetector()

    private var timer: Timer?
    private(set) var currentDigit: Int?
    let holdDuration: TimeInterval
    private let store: HotbarStore

    convenience init() {
        self.init(holdDuration: 0.5, store: .shared)
    }

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
        guard store.windows.indices.contains(store.selectedIndex) else {
            cancel()
            return
        }
        let selectedWindow = store.windows[store.selectedIndex]
        store.assignSlot(index: digit, windowInfo: selectedWindow)
        NotificationCenter.default.post(name: .hotbarSlotAssigned, object: digit)
        cancel()
    }
}

extension Notification.Name {
    static let hotbarSlotAssigned = Notification.Name("hotbarSlotAssigned")
}
