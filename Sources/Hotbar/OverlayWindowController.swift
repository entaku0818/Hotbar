import AppKit
import SwiftUI

final class OverlayWindowController: NSObject {
    private var panel: NSPanel?
    private(set) var isVisible = false

    override init() {
        super.init()
        createPanel()
    }

    private func createPanel() {
        let store = HotbarStore.shared

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
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

        panel.contentView = NSHostingView(rootView: overlayView)
        self.panel = panel

        // ESC / スロット割り当て通知でパネルを閉じる
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hideOverlay),
            name: .hideOverlay,
            object: nil
        )
    }

    func show() {
        guard let panel = panel else { return }

        HotbarStore.shared.refreshWindows()

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let panelSize = panel.frame.size
            let originX = screenFrame.midX - panelSize.width / 2
            let originY = screenFrame.midY - panelSize.height / 2
            panel.setFrameOrigin(NSPoint(x: originX, y: originY))
        }

        panel.orderFrontRegardless()
        isVisible = true
    }

    func hide() {
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
