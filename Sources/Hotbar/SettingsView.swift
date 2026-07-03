import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @State private var hotkey = HotkeyPreference.load()
    @State private var isRecording = false
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)
    @State private var recorderMonitor: Any?

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Toggle overlay")
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
                Text("Click, then press a new shortcut. At least one modifier (⌘⌥⇧⌃) is required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Reset to ⌥Space") {
                    hotkey = .default
                    hotkey.save()
                }
                .disabled(hotkey == .default)
            } header: {
                Text("Keyboard Shortcut")
            }

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
                            // Revert toggle on failure
                            launchAtLogin = (SMAppService.mainApp.status == .enabled)
                        }
                    }
            } header: {
                Text("General")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 260)
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        recorderMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // ESC cancels recording
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
            guard candidate.hasModifier else { return nil } // require a modifier
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
