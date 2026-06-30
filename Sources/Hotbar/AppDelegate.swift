import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayWindowController: OverlayWindowController?
    private var hotKeyManager: HotKeyManager?
    private var statusItem: NSStatusItem?
    private var onboardingWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        setupOverlay()
        setupHotKeys()
        showOnboardingIfNeeded()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: "Hotbar")
            button.action = #selector(statusItemClicked)
            button.target = self
        }
    }

    private func setupOverlay() {
        overlayWindowController = OverlayWindowController()
    }

    private func setupHotKeys() {
        hotKeyManager = HotKeyManager(overlayController: overlayWindowController!)
        hotKeyManager?.start()
    }

    @objc private func statusItemClicked() {
        overlayWindowController?.toggle()
    }

    private func showOnboardingIfNeeded() {
        let hasSeenOnboarding = UserDefaults.standard.bool(forKey: "hasSeenOnboarding")
        guard !hasSeenOnboarding else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.showOnboarding()
        }
    }

    func showOnboarding() {
        let onboardingView = OnboardingView {
            self.onboardingWindowController?.close()
            self.onboardingWindowController = nil
            UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 450),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Hotbar"
        window.contentView = NSHostingView(rootView: onboardingView)
        window.center()
        window.isReleasedWhenClosed = false

        onboardingWindowController = NSWindowController(window: window)
        onboardingWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
