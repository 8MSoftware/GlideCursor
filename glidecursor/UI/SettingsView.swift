import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var registry = DeviceRegistry.shared
    @ObservedObject var glide = GlideController.shared
    @State private var isRecording = false
    @State private var recordingPrecision = false
    @State private var keyMonitor: Any?
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    /// 設定のタブ。最後に開いていたタブを覚える
    enum Tab: String, CaseIterable { case glide, precision }
    @AppStorage("v2.settingsTab") private var tab: Tab = .glide

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

            warnings

            Picker("", selection: $tab) {
                Text("Glide").tag(Tab.glide)
                Text("Precision mode").tag(Tab.precision)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)

            switch tab {
            case .glide: glideTab
            case .precision: precisionTab
            }

            Divider()

            HStack {
                Button("Reset to Defaults") { settings.resetToDefaults() }
                    .font(.caption)
                    .help("Resets the sliders. Devices and shortcuts are kept.")
                Spacer()
                appMenu
            }
        }
        // 中身の幅を先に決めてから余白を付ける(長い文やタブがはみ出さないように)
        .frame(width: 288, alignment: .leading)
        .padding(16)
    }

    @ViewBuilder private var warnings: some View {
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
    }

    // MARK: 慣性

    private var glideTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Glide on these devices").font(.subheadline).foregroundColor(.secondary)
                if registry.devices.isEmpty {
                    Text(settings.isEnabled ? LocalizedStringKey("Move the cursor to detect devices…") : LocalizedStringKey("Turn GlideCursor on to detect devices."))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(registry.devices) { device in
                        HStack {
                            Image(systemName: icon(for: device.kind))
                                .frame(width: 20)
                                .foregroundColor(device.connected ? .primary : .secondary)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(device.displayName).lineLimit(1)
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

            switchRow("Ignore the tap that stops a glide", isOn: $settings.suppressClickOnStop,
                      note: "With tap to click, touching the trackpad to stop a glide won't also click.")

            Divider()

            shortcutRow("On/off shortcut", enabled: $settings.isGlobalShortcutEnabled,
                        keyCode: settings.globalShortcutKeyCode, modifiers: settings.globalShortcutModifiers, precision: false)
        }
    }

    // MARK: 精密モード

    private var precisionTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            switchRow("Use precision mode", isOn: $settings.precisionEnabled,
                      note: "Slows the cursor down for fine positioning, for example in a drawing app. No glide while it is on.")

            if settings.precisionEnabled {
                slider("Precision speed", value: $settings.precisionFactor, in: 0.1...0.9, step: 0.1,
                       format: String(format: "×%.1f", settings.precisionFactor),
                       note: "The cursor moves this much slower in precision mode.")

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("How to start").font(.subheadline).foregroundColor(.secondary)

                    Toggle("Keyboard shortcut", isOn: $settings.precisionUseShortcut).toggleStyle(.checkbox)
                    if settings.precisionUseShortcut {
                        VStack(alignment: .leading, spacing: 4) {
                            shortcutRow(nil, enabled: nil, keyCode: settings.precisionKeyCode,
                                        modifiers: settings.precisionModifiers, precision: true)
                            Text("Press it once to start, and again to leave.")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        .padding(.leading, 20)
                    }

                    Toggle("Hold a modifier key", isOn: $settings.precisionUseModifier).toggleStyle(.checkbox)
                    if settings.precisionUseModifier {
                        VStack(alignment: .leading, spacing: 4) {
                            Picker("Key", selection: $settings.precisionModifier) {
                                Text(verbatim: "fn").tag(SettingsManager.PrecisionModifier.fn)
                                Text(verbatim: "⌃ Control").tag(SettingsManager.PrecisionModifier.control)
                                Text(verbatim: "⌥ Option").tag(SettingsManager.PrecisionModifier.option)
                                Text(verbatim: "⇧ Shift").tag(SettingsManager.PrecisionModifier.shift)
                                Text(verbatim: "⌘ Command").tag(SettingsManager.PrecisionModifier.command)
                            }
                            .fixedSize()
                            Text("Slow while you hold the key. If holding fn opens the emoji picker, set “Press 🌐 key to” to “Do Nothing” in Keyboard settings.")
                                .font(.caption).foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.leading, 20)
                    }

                    Toggle("Double-tap and hold", isOn: $settings.precisionUseHold).toggleStyle(.checkbox)
                    if settings.precisionUseHold {
                        VStack(alignment: .leading, spacing: 6) {
                            slider("Hold for", value: $settings.precisionHoldDelay, in: 0...3, step: 0.1,
                                   format: String(format: "%.1f s", settings.precisionHoldDelay),
                                   note: "Double-tap, keep your finger down for this long, and precision mode starts. Lift to leave.")
                            Label("If you use double-tap to drag (Dragging or Drag Lock in the trackpad settings), the two clash. Use the keyboard shortcut instead. With tap to click, the first tap also clicks.",
                                  systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.leading, 20)
                    }
                }
            }
        }
    }

    /// ショートカット1つ分の行:名前とスイッチ / キーと変更ボタン
    private func shortcutRow(_ title: LocalizedStringKey?, enabled: Binding<Bool>?, keyCode: Int, modifiers: Int, precision: Bool) -> some View {
        let on = enabled?.wrappedValue ?? true
        return VStack(alignment: .leading, spacing: 6) {
            if let title {
                HStack {
                    Text(title)
                    Spacer()
                    if let enabled { Toggle("", isOn: enabled).toggleStyle(.switch).controlSize(.small).labelsHidden() }
                }
            }
            HStack {
                Text(shortcutString(keyCode: keyCode, modifiers: modifiers))
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(6)
                    .opacity(on ? 1 : 0.4)
                Spacer()
                Button(isRecording && recordingPrecision == precision ? "Press Key…" : "Change") { startRecording(precision: precision) }
                    .font(.caption)
                    .disabled(isRecording || !on)
            }
        }
    }

    /// 名前とスイッチを1行に、説明をその下に
    private func switchRow(_ title: LocalizedStringKey, isOn: Binding<Bool>, note: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Toggle("", isOn: isOn).toggleStyle(.switch).controlSize(.small).labelsHidden()
            }
            Text(note).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 歯車ボタンのメニュー：言語・ログイン時に開く・Web サイト・終了
    private var appMenu: some View {
        Menu {
            Picker("Language", selection: Binding(get: { AppLanguage.current }, set: { $0.apply() })) {
                Text("System Default").tag(AppLanguage.system)
                Text(verbatim: "日本語").tag(AppLanguage.ja)
                Text(verbatim: "English").tag(AppLanguage.en)
            }
            .pickerStyle(.menu)
            Toggle("Open at Login", isOn: Binding(get: { launchAtLogin }, set: {
                LaunchAtLogin.set($0)
                launchAtLogin = LaunchAtLogin.isEnabled
            }))
            Divider()
            Button("Donate…") { Donation.open() }
            Button("Website") { NSWorkspace.shared.open(Self.websiteURL) }
            Divider()
            Button("Quit GlideCursor") { NSApplication.shared.terminate(nil) }
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }

    private static let websiteURL = URL(string: "https://glidecursor.8m-software.com/")!

    private func slider(_ title: LocalizedStringKey, value: Binding<Double>, in range: ClosedRange<Double>, step: Double,
                        format: String, note: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(verbatim: format).monospacedDigit().foregroundColor(.secondary)
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

    private func startRecording(precision: Bool) {
        isRecording = true
        recordingPrecision = precision
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isRecording else { return event }
            var mods = 0
            if event.modifierFlags.contains(.command) { mods |= 256 }   // cmdKey
            if event.modifierFlags.contains(.shift) { mods |= 512 }     // shiftKey
            if event.modifierFlags.contains(.option) { mods |= 2048 }   // optionKey
            if event.modifierFlags.contains(.control) { mods |= 4096 }  // controlKey
            if recordingPrecision {
                settings.precisionKeyCode = Int(event.keyCode)
                settings.precisionModifiers = mods
            } else {
                settings.globalShortcutKeyCode = Int(event.keyCode)
                settings.globalShortcutModifiers = mods
            }
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
