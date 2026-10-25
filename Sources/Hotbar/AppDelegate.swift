import AppKit
import SwiftUI
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayWindowController: OverlayWindowController?
    private var hotKeyManager: HotKeyManager?
    private var statusItem: NSStatusItem?
    private var onboardingWindowController: NSWindowController?
    private var settingsWindowController: NSWindowController?
    private var licenseGateWindowController: NSWindowController?
    private var permissionRetryTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit-test hosts must not install global shortcuts or request macOS permissions.
        guard NSClassFromString("XCTestCase") == nil,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        NotificationCenter.default.addObserver(self, selector: #selector(languageChanged),
                                               name: .hotbarLanguageChanged, object: nil)
        setupOverlay()
        setupHotKeys()
        requestAccessibilityIfNeeded()
        showOnboardingIfNeeded()

        if CommandLine.arguments.contains("--show-settings") {
            DispatchQueue.main.async { self.openSettings() }
        }
        if CommandLine.arguments.contains("--show-switcher") {
            DispatchQueue.main.async { self.showSwitcher() }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showLicenseGate),
            name: .licenseGateRequested,
            object: nil
        )

        // Re-check the stored license against Polar on every launch. Offline
        // launches fall back to the 14-day grace period inside LicenseManager.
        Task { @MainActor in
            await LicenseManager.shared.revalidate()
        }
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
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        }
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: "Hotbar")
        }

        let menu = NSMenu()

        let showItem = NSMenuItem(title: L10n.text("Show Switcher"), action: #selector(showSwitcher), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: L10n.text("Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let onboardingItem = NSMenuItem(title: L10n.text("Show Tutorial"), action: #selector(showTutorial), keyEquivalent: "")
        onboardingItem.target = self
        menu.addItem(onboardingItem)

        menu.addItem(.separator())

        let licenseItem = NSMenuItem(title: L10n.text("License…"), action: #selector(showLicenseGate), keyEquivalent: "")
        licenseItem.target = self
        menu.addItem(licenseItem)

        let updateItem = NSMenuItem(title: L10n.text("Check for Updates…"), action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: L10n.text("Quit Hotbar"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func languageChanged() {
        setupStatusItem()
        settingsWindowController?.window?.title = L10n.text("Hotbar Settings")
        licenseGateWindowController?.window?.title = L10n.text("Hotbar License")
        onboardingWindowController?.window?.title = L10n.text("Welcome to Hotbar")
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
            window.title = L10n.text("Hotbar Settings")
            window.contentView = NSHostingView(rootView: LocalizedContent { SettingsView() })
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

    // MARK: - Licensing

    @objc func showLicenseGate() {
        if licenseGateWindowController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = L10n.text("Hotbar License")
            window.contentView = NSHostingView(rootView: LocalizedContent { LicenseGateView(licenseManager: LicenseManager.shared) })
            window.center()
            window.isReleasedWhenClosed = false
            licenseGateWindowController = NSWindowController(window: window)
        }
        licenseGateWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Updates

    @objc func checkForUpdates() {
        Task { @MainActor in
            let result = await UpdateChecker.shared.checkForUpdate()
            self.presentUpdateResult(result)
        }
    }

    @MainActor
    private func presentUpdateResult(_ result: UpdateCheckResult) {
        let alert = NSAlert()
        switch result {
        case .upToDate:
            alert.messageText = L10n.text("You're up to date")
            alert.informativeText = L10n.text("Hotbar is on the latest version.")
            alert.addButton(withTitle: L10n.text("OK"))
            alert.runModal()
        case .updateAvailable(let version, let url):
            alert.messageText = L10n.format("Update available: %@", version)
            alert.informativeText = L10n.text("Open the release page to download the latest version.")
            alert.addButton(withTitle: L10n.text("Open Release Page"))
            alert.addButton(withTitle: L10n.text("Cancel"))
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(url)
            }
        case .checkFailed:
            alert.messageText = L10n.text("Couldn't check for updates")
            alert.informativeText = L10n.text("Please check your internet connection and try again.")
            alert.addButton(withTitle: L10n.text("OK"))
            alert.runModal()
        }
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
        window.title = L10n.text("Welcome to Hotbar")
        window.contentView = NSHostingView(rootView: LocalizedContent { onboardingView })
        window.center()
        window.isReleasedWhenClosed = false

        onboardingWindowController = NSWindowController(window: window)
        onboardingWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
