import AppKit
import SwiftUI
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayWindowController: OverlayWindowController?
    private var hotKeyManager: HotKeyManager?
    private var statusItem: NSStatusItem?
    private var onboardingWindowController: NSWindowController?
    private var settingsWindowController: NSWindowController?
    private var permissionRetryTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        setupOverlay()
        setupHotKeys()
        requestAccessibilityIfNeeded()
        showOnboardingIfNeeded()
    }

    private func requestAccessibilityIfNeeded() {
        // Prompt the system dialog if permission is not yet granted.
        // Using AXIsProcessTrustedWithOptions so macOS re-validates the
        // current binary — prevents stale TCC entries after reinstall.
        guard !AXIsProcessTrusted() else { return }

        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        AXIsProcessTrustedWithOptions(opts as CFDictionary)

        // CGEventTap creation fails without permission; retry once granted
        // so hotkeys start working without an app restart.
        permissionRetryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if AXIsProcessTrusted() {
                self.hotKeyManager?.restartTapIfNeeded()
                timer.invalidate()
                self.permissionRetryTimer = nil
            }
        }
    }

    // MARK: - Status bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: "Hotbar")
        }

        let menu = NSMenu()

        let showItem = NSMenuItem(title: "Show Switcher", action: #selector(showSwitcher), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let onboardingItem = NSMenuItem(title: "Show Tutorial", action: #selector(showTutorial), keyEquivalent: "")
        onboardingItem.target = self
        menu.addItem(onboardingItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Hotbar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func showSwitcher() {
        overlayWindowController?.toggle()
    }

    @objc private func showTutorial() {
        showOnboarding()
    }

    // MARK: - Settings

    @objc func openSettings() {
        if settingsWindowController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Hotbar Settings"
            window.contentView = NSHostingView(rootView: SettingsView())
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindowController = NSWindowController(window: window)
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setupOverlay() {
        overlayWindowController = OverlayWindowController()
    }

    private func setupHotKeys() {
        guard let controller = overlayWindowController else { return }
        hotKeyManager = HotKeyManager(overlayController: controller)
        hotKeyManager?.start()
    }

    // MARK: - Onboarding

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
