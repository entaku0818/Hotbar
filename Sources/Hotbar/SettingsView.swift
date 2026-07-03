import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            ShortcutSettingsTab()
                .tabItem { Label("Shortcut", systemImage: "keyboard") }
            AppearanceSettingsTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            FiltersSettingsTab()
                .tabItem { Label("Filters", systemImage: "line.3.horizontal.decrease.circle") }
        }
        .frame(width: 480, height: 400)
    }
}

// MARK: - General

struct GeneralSettingsTab: View {
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)
    @State private var screenRecordingGranted = CGPreflightScreenCaptureAccess()

    var body: some View {
        Form {
            Section {
                Toggle("Launch Hotbar at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = (SMAppService.mainApp.status == .enabled)
                        }
                    }
            } header: {
                Text("Startup")
            }

            Section {
                if screenRecordingGranted {
                    Label("Window previews enabled", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Text("Optional: window previews (thumbnails) and exact window titles need Screen Recording permission. Without it, app icons are shown.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Enable window previews…") {
                        CGRequestScreenCaptureAccess()
                    }
                }
            } header: {
                Text("Window Previews")
            }
        }
        .formStyle(.grouped)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            screenRecordingGranted = CGPreflightScreenCaptureAccess()
        }
    }
}

// MARK: - Shortcut

struct ShortcutSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var hotkey = HotkeyPreference.load()
    @State private var isRecording = false
    @State private var recorderMonitor: Any?

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Show switcher")
                    Spacer()
                    Button {
                        isRecording ? stopRecording() : startRecording()
                    } label: {
                        Text(isRecording ? "Press keys…" : hotkey.displayString)
                            .font(.system(.body, design: .monospaced))
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(.bordered)
                    .tint(isRecording ? .orange : nil)
                }
                Text("Click, then press a new shortcut. At least one modifier (⌘⌥⇧⌃) is required. Shift+shortcut cycles backwards.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Reset to default (⌥⇥)") {
                    hotkey = .default
                    hotkey.save()
                }
                .disabled(hotkey == .default)
            } header: {
                Text("Keyboard Shortcut")
            }

            Section {
                Picker("Switching style", selection: $settings.holdMode) {
                    Text("Hold (AltTab-style)").tag(true)
                    Text("Toggle").tag(false)
                }
                .pickerStyle(.radioGroup)
                Text(settings.holdMode
                    ? "Hold the modifier, tap the key to cycle windows, release to switch."
                    : "Press once to open, click or press ⌘1–9 to switch, ESC to close.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Behavior")
            }
        }
        .formStyle(.grouped)
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        recorderMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53, event.modifierFlags.intersection([.command, .option, .shift, .control]).isEmpty {
                stopRecording()
                return nil
            }
            let candidate = HotkeyPreference(
                keyCode: event.keyCode,
                option: event.modifierFlags.contains(.option),
                command: event.modifierFlags.contains(.command),
                shift: event.modifierFlags.contains(.shift),
                control: event.modifierFlags.contains(.control)
            )
            guard candidate.hasModifier else { return nil }
            hotkey = candidate
            hotkey.save()
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = recorderMonitor {
            NSEvent.removeMonitor(monitor)
            recorderMonitor = nil
        }
    }
}

// MARK: - Appearance

struct AppearanceSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Thumbnail size")
                        Spacer()
                        Text("\(Int(settings.thumbnailSize)) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.thumbnailSize, in: 120...220, step: 10)
                }
                Toggle("Show window titles", isOn: $settings.showTitles)
            } header: {
                Text("Window Grid")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Filters

struct FiltersSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var store = HotbarStore.shared

    private var appNames: [String] {
        Array(Set(store.windows.map(\.appName)).union(settings.excludedApps)).sorted()
    }

    var body: some View {
        Form {
            Section {
                if appNames.isEmpty {
                    Text("Open the switcher once to populate the app list.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appNames, id: \.self) { name in
                        Toggle(name, isOn: Binding(
                            get: { !settings.excludedApps.contains(name) },
                            set: { shown in
                                if shown {
                                    settings.excludedApps.remove(name)
                                } else {
                                    settings.excludedApps.insert(name)
                                }
                            }
                        ))
                    }
                }
            } header: {
                Text("Show windows from")
            } footer: {
                Text("Unchecked apps are hidden from the switcher.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { store.refreshWindows() }
    }
}
