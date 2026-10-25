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

    func show() {
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

        panel.orderFrontRegardless()
        isVisible = true
    }

    static func panelSize(in visibleFrame: CGRect) -> CGSize {
        CGSize(width: (visibleFrame.width * 0.85).rounded(.down),
               height: (visibleFrame.height * 0.82).rounded(.down))
    }

    func hide() {
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
