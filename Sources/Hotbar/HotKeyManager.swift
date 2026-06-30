import AppKit
import Carbon

final class HotKeyManager {
    private weak var overlayController: OverlayWindowController?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(overlayController: OverlayWindowController) {
        self.overlayController = overlayController
    }

    func start() {
        // Global monitor: ⌘+Space でオーバーレイ表示
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        // Local monitor: オーバーレイ表示中のキー操作
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            return self?.handleLocalKeyEvent(event)
        }
    }

    func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        // ⌘+Space
        if event.modifierFlags.contains(.command) && event.keyCode == 49 {
            DispatchQueue.main.async {
                self.overlayController?.toggle()
            }
        }
    }

    private func handleLocalKeyEvent(_ event: NSEvent) -> NSEvent? {
        guard let controller = overlayController, controller.isVisible else {
            return event
        }

        // ESC で閉じる
        if event.keyCode == 53 {
            controller.hide()
            return nil
        }

        // ⌘+Space でトグル
        if event.modifierFlags.contains(.command) && event.keyCode == 49 {
            controller.toggle()
            return nil
        }

        // ⌘+1〜9 でスロットジャンプ
        if event.modifierFlags.contains(.command),
           let char = event.charactersIgnoringModifiers,
           let digit = Int(char),
           digit >= 1 && digit <= 9 {
            let store = HotbarStore.shared
            store.activateSlot(index: digit)
            controller.hide()
            return nil
        }

        // 数字長押し検出（スイッチャー表示中）
        if !event.modifierFlags.contains(.command),
           let char = event.charactersIgnoringModifiers,
           let digit = Int(char),
           digit >= 1 && digit <= 9 {
            HoldKeyDetector.shared.start(digit: digit)
            return nil
        }

        return event
    }

    deinit {
        stop()
    }
}

// MARK: - Long-press detector for slot registration

final class HoldKeyDetector {
    static let shared = HoldKeyDetector()

    private var timer: Timer?
    private var currentDigit: Int?
    private let holdDuration: TimeInterval = 0.5

    func start(digit: Int) {
        if currentDigit == digit {
            // Already tracking this digit
            return
        }
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

    private func triggerRegister() {
        guard let digit = currentDigit else { return }
        let store = HotbarStore.shared
        guard let selectedWindow = store.windows.indices.contains(store.selectedIndex)
            ? store.windows[store.selectedIndex] : nil else {
            cancel()
            return
        }
        store.assignSlot(index: digit, windowInfo: selectedWindow)
        NotificationCenter.default.post(name: .hotbarSlotAssigned, object: digit)
        cancel()
    }
}

extension Notification.Name {
    static let hotbarSlotAssigned = Notification.Name("hotbarSlotAssigned")
}
