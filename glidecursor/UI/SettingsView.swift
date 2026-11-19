import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var registry = DeviceRegistry.shared
    @ObservedObject var glide = GlideController.shared
    @State private var isRecording = false
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Text("GlideCursor").font(.headline)
                Spacer()
                Toggle("", isOn: Binding(get: { settings.isEnabled }, set: { settings.setEnabled($0) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            if settings.isEnabled && !glide.tapRunning {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Accessibility permission is needed. GlideCursor can't see or move the cursor until it is allowed.",
                          systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Button("Open Accessibility Settings") {
                        Permissions.requestAccessibilityIfNeeded()
                        Permissions.openAccessibilitySettings()
                    }
                    .font(.caption)
                    Text("If GlideCursor is already listed and on, remove it with − and add it again.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if !GlideController.shared.multitouchAvailable {
                Label("Touch detection is unavailable on this macOS version. Gliding is disabled.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            Divider()

            // Devices
            VStack(alignment: .leading, spacing: 6) {
                Text("Glide on these devices").font(.subheadline).foregroundColor(.secondary)
                if registry.devices.isEmpty {
                    Text(settings.isEnabled ? "Move the cursor to detect devices…" : "Turn GlideCursor on to detect devices.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(registry.devices) { device in
                        HStack {
                            Image(systemName: icon(for: device.kind))
                                .frame(width: 20)
                                .foregroundColor(device.connected ? .primary : .secondary)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(device.name).lineLimit(1)
                                if !device.connected {
                                    Text("Not connected").font(.caption2).foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { settings.isDeviceEnabled(device) },
                                set: { settings.setDevice(device, enabled: $0) }))
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .labelsHidden()
                        }
                    }
                }
            }

            Divider()

            // Sliders
            VStack(alignment: .leading, spacing: 12) {
                slider("Glide length", value: $settings.glideLength, in: 0.15...1.5, step: 0.05,
                       format: String(format: "%.2f s", settings.glideLength),
                       note: "How long the cursor keeps gliding after you lift your finger.")
                slider("Speed", value: $settings.speedMultiplier, in: 0.5...2.5, step: 0.1,
                       format: String(format: "%.1f×", settings.speedMultiplier),
                       note: "Multiplies the speed at the moment you lift your finger.")
                slider("Flick threshold", value: $settings.flickThreshold, in: 100...2000, step: 50,
                       format: "\(Int(settings.flickThreshold)) px/s",
                       note: "Lifting slower than this does not glide. Lower = easier to trigger.")
                slider("Max speed", value: $settings.maxSpeed, in: 2000...20000, step: 500,
                       format: "\(Int(settings.maxSpeed)) px/s",
                       note: "Caps the starting speed of a glide.")
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Ignore the tap that stops a glide", isOn: $settings.suppressClickOnStop)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Text("With tap to click, touching the trackpad to stop a glide won't also click.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Global Shortcut
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Global Shortcut").font(.subheadline).foregroundColor(.secondary)
                    Spacer()
                    Toggle("", isOn: $settings.isGlobalShortcutEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }
                if settings.isGlobalShortcutEnabled {
                    HStack {
                        Text(shortcutString(keyCode: settings.globalShortcutKeyCode, modifiers: settings.globalShortcutModifiers))
                            .font(.system(.body, design: .monospaced))
                            .padding(4)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(6)
                        Spacer()
                        Button(isRecording ? "Press Key…" : "Change") { startRecording() }
                            .font(.caption)
                            .disabled(isRecording)
                    }
                }
            }

            Divider()

            HStack {
                Button("Reset to Defaults") { settings.resetToDefaults() }
                Spacer()
                Link("Website", destination: URL(string: "https://yaoyorozu-software.com/glidecursor/")!)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .font(.caption)
        }
        .padding()
        .frame(width: 320)
    }

    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double,
                        format: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(format).monospacedDigit().foregroundColor(.secondary)
            }
            Slider(value: value, in: range, step: step)
            Text(note).font(.caption).foregroundColor(.secondary)
        }
    }

    private func icon(for kind: GlideDevice.Kind) -> String {
        switch kind {
        case .trackpad: return "rectangle.and.hand.point.up.left"
        case .magicMouse: return "magicmouse"
        case .mouse: return "computermouse"
        }
    }

    private func startRecording() {
        isRecording = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isRecording else { return event }
            var mods = 0
            if event.modifierFlags.contains(.command) { mods |= 256 }   // cmdKey
            if event.modifierFlags.contains(.shift) { mods |= 512 }     // shiftKey
            if event.modifierFlags.contains(.option) { mods |= 2048 }   // optionKey
            if event.modifierFlags.contains(.control) { mods |= 4096 }  // controlKey
            settings.globalShortcutKeyCode = Int(event.keyCode)
            settings.globalShortcutModifiers = mods
            isRecording = false
            if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
            return nil
        }
    }

    private static let keyNames: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q",
        13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
        24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I",
        35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M",
        47: ".", 50: "`",
    ]

    private func shortcutString(keyCode: Int, modifiers: Int) -> String {
        var s = ""
        if modifiers & 4096 != 0 { s += "⌃ " }
        if modifiers & 2048 != 0 { s += "⌥ " }
        if modifiers & 512 != 0 { s += "⇧ " }
        if modifiers & 256 != 0 { s += "⌘ " }
        return s + (Self.keyNames[keyCode] ?? "Key(\(keyCode))")
    }
}
