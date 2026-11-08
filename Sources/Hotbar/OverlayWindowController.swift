import AppKit
import SwiftUI

final class OverlayWindowController: NSObject {
    private var panel: NSPanel?
    /// True while a switcher session is active — even before the panel is on screen.
    private(set) var isVisible = false
    private var pendingReveal: DispatchWorkItem?

    override init() {
        super.init()
        createPanel()
    }

    private func createPanel() {
        let store = HotbarStore.shared

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize(in: NSScreen.main?.visibleFrame ?? .zero)),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true

        let overlayView = OverlayView()
            .environmentObject(store)

        panel.contentView = NSHostingView(rootView: LocalizedContent { overlayView })
        self.panel = panel

        // ESC / スロット割り当て通知でパネルを閉じる
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hideOverlay),
            name: .hideOverlay,
            object: nil
        )
    }

    /// Delay before the panel appears on a held-modifier hotkey. Releasing within it switches to the
    /// previous window without the list ever flashing on screen (like ⌘Tab).
    static let quickSwitchRevealDelay: TimeInterval = 0.15

    func show(revealDelay: TimeInterval = 0) {
        guard let panel = panel else { return }

        guard !LicenseManager.shared.isGated else {
            NotificationCenter.default.post(name: .licenseGateRequested, object: nil)
            return
        }

        HotbarStore.shared.refreshWindows()

        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let screenFrame = screen.visibleFrame
            let panelSize = Self.panelSize(in: screenFrame)
            let origin = AppSettings.shared.overlayPosition.origin(in: screenFrame, panelSize: panelSize)
            panel.setFrame(NSRect(origin: origin, size: panelSize), display: true)
        }

        isVisible = true
        pendingReveal?.cancel()
        guard revealDelay > 0 else {
            panel.orderFrontRegardless()
            return
        }
        let reveal = DispatchWorkItem { [weak self] in
            guard let self, self.isVisible else { return }
            self.pendingReveal = nil
            panel.orderFrontRegardless()
        }
        pendingReveal = reveal
        DispatchQueue.main.asyncAfter(deadline: .now() + revealDelay, execute: reveal)
    }

    static func panelSize(in visibleFrame: CGRect) -> CGSize {
        CGSize(width: (visibleFrame.width * 0.85).rounded(.down),
               height: (visibleFrame.height * 0.82).rounded(.down))
    }

    func hide() {
        pendingReveal?.cancel()
        pendingReveal = nil
        HotbarStore.shared.cancelThumbnailLoading()
        panel?.orderOut(nil)
        isVisible = false
        HoldKeyDetector.shared.cancel()
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    @objc private func hideOverlay() {
        hide()
    }
}

extension Notification.Name {
    static let hideOverlay = Notification.Name("hideOverlay")
}
