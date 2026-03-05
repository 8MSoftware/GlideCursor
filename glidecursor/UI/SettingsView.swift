import SwiftUI

struct SettingsView: View {
    @StateObject var settings = SettingsManager.shared
    @StateObject var eventTap = EventTapManager.shared
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("GlideCursor")
                    .font(.headline)
                Spacer()
                Toggle("", isOn: $settings.isEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: settings.isEnabled) { _, newValue in
                        if newValue {
                            EventTapManager.shared.start()
                        } else {
                            EventTapManager.shared.stop()
                        }
                    }
            }
            
            Divider()
            
            // Global Shortcut
            VStack(alignment: .leading) {
                HStack {
                    Text("Global Shortcut")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Toggle("", isOn: $settings.isGlobalShortcutEnabled)
                        .toggleStyle(.switch)
                }
                
                if settings.isGlobalShortcutEnabled {
                    HStack {
                        Text(shortcutString(keyCode: settings.globalShortcutKeyCode, modifiers: settings.globalShortcutModifiers))
                            .font(.system(.body, design: .monospaced))
                            .padding(6)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(6)
                        
                        Spacer()
                        
                        Button(isRecording ? "Press Key..." : "Change") {
                            startRecording()
                        }
                        .font(.caption)
                        .disabled(isRecording)
                    }
                }
            }
            .padding(.vertical, 5)
            
            Divider()
            
            /*
            // Device
            // Device List
            VStack(alignment: .leading) {
                Text("Devices")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if eventTap.knownDevices.isEmpty {
                    Text("Move cursor to detect devices...")
                        .foregroundColor(.secondary)
                        .font(.caption)
                        .padding(.vertical, 5)
                } else {
                    ForEach(Array(eventTap.knownDevices).sorted(by: { $0.id < $1.id }), id: \.self) { device in
                        HStack {
                            VStack(alignment: .leading) {
                                Text("ID: \(device.id) (Type: \(device.subtype))")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                if device == eventTap.lastSeenDevice {
                                    Text("(Active Now)")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                }
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: Binding(
                                get: { settings.enabledDevices.contains(device) },
                                set: { _ in settings.toggleDevice(device) }
                            ))
                            .toggleStyle(.switch)
                            .labelsHidden()
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            
            Divider()
            */
            
            // Sliders
            VStack(alignment: .leading, spacing: 15) {
                VStack(alignment: .leading) {
                    Text("Flick Sensitivity: \(String(format: "%.1f", settings.flickSensitivity))")
                    Slider(value: $settings.flickSensitivity, in: 1.0...10.0, step: 0.5) {
                        Text("Sensitivity")
                    } minimumValueLabel: {
                        Text("High") // Low value = High sensitivity (wait, logic is velocity > threshold)
                                     // Actually: velocity > threshold. So LOWER threshold = EASIER to trigger = HIGHER sensitivity.
                                     // Let's make the slider intuitive: "Sensitivity".
                                     // If we want "High Sensitivity", we want LOW threshold.
                                     // Let's keep it simple: "Activation Threshold" (Low = Sensitive)
                    } maximumValueLabel: {
                        Text("Low")
                    }
                    Text("Lower value = Easier to trigger")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading) {
                    Text("Speed: \(String(format: "%.1f", settings.speedMultiplier))x")
                    Slider(value: $settings.speedMultiplier, in: 0.5...3.0, step: 0.1)
                    Text("Multiplies the initial flick velocity.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading) {
                    Text("Friction: \(String(format: "%.2f", settings.friction))")
                    Slider(value: $settings.friction, in: 0.80...0.99, step: 0.01)
                    Text("Higher value = Glides longer (less friction).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading) {
                    Text("Max Velocity: \(Int(settings.maxVelocity))")
                    Slider(value: $settings.maxVelocity, in: 10...100, step: 5)
                    Text("Caps the maximum speed to prevent loss of control.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            // Experimental
            VStack(alignment: .leading, spacing: 6) {
                Text("Experimental")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Toggle("Suppress Click on Glide Stop", isOn: $settings.suppressClickOnStop)
                    .toggleStyle(.switch)
                Text("Prevents the tap that stops a glide from registering as a click. The first click after stopping may be lost.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            Button("Reset to Defaults") {
                settings.resetToDefaults()
            }
            .font(.caption)
            
            Button("Reset Onboarding & Quit") {
                settings.hasLaunchedBefore = false
                NSApplication.shared.terminate(nil)
            }
            .font(.caption)
            .foregroundColor(.red)
            
            Divider()
            
            // Links
            Link("Visit Website", destination: URL(string: "https://yaoyorozu-software.com/glidecursor/")!)
                .font(.footnote)
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding()
        .frame(width: 300)
    }
    
    @State private var isRecording = false
    
    private func startRecording() {
        isRecording = true
        
        // Monitor local events for the next key press
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if self.isRecording {
                // Convert Cocoa modifiers to Carbon modifiers
                var carbonModifiers = 0
                if event.modifierFlags.contains(.command) { carbonModifiers |= 256 } // cmdKey
                if event.modifierFlags.contains(.shift) { carbonModifiers |= 512 } // shiftKey
                if event.modifierFlags.contains(.option) { carbonModifiers |= 2048 } // optionKey
                if event.modifierFlags.contains(.control) { carbonModifiers |= 4096 } // controlKey
                
                DispatchQueue.main.async {
                    self.settings.globalShortcutKeyCode = Int(event.keyCode)
                    self.settings.globalShortcutModifiers = carbonModifiers
                    self.isRecording = false
                }
                return nil // Consume event
            }
            return event
        }
    }
    
    private func shortcutString(keyCode: Int, modifiers: Int) -> String {
        var str = ""
        if (modifiers & 4096) != 0 { str += "⌃ " }
        if (modifiers & 2048) != 0 { str += "⌥ " }
        if (modifiers & 512) != 0 { str += "⇧ " }
        if (modifiers & 256) != 0 { str += "⌘ " }
        
        // Simple mapping for common keys, fallback to code
        switch keyCode {
        case 0: str += "A"
        case 1: str += "S"
        case 2: str += "D"
        case 3: str += "F"
        case 4: str += "H"
        case 5: str += "G"
        case 6: str += "Z"
        case 7: str += "X"
        case 8: str += "C"
        case 9: str += "V"
        case 11: str += "B"
        case 12: str += "Q"
        case 13: str += "W"
        case 14: str += "E"
        case 15: str += "R"
        case 16: str += "Y"
        case 17: str += "T"
        case 18: str += "1"
        case 19: str += "2"
        case 20: str += "3"
        case 21: str += "4"
        case 22: str += "6"
        case 23: str += "5"
        case 24: str += "="
        case 25: str += "9"
        case 26: str += "7"
        case 27: str += "-"
        case 28: str += "8"
        case 29: str += "0"
        case 30: str += "]"
        case 31: str += "O"
        case 32: str += "U"
        case 33: str += "["
        case 34: str += "I"
        case 35: str += "P"
        case 37: str += "L"
        case 38: str += "J"
        case 39: str += "'"
        case 40: str += "K"
        case 41: str += ";"
        case 42: str += "\\"
        case 43: str += ","
        case 44: str += "/"
        case 45: str += "N"
        case 46: str += "M"
        case 47: str += "."
        case 50: str += "`"
        default: str += "Key(\(keyCode))"
        }
        
        return str
    }
}
