import Foundation
import Combine



class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "isEnabled") }
    }
    
    @Published var speedMultiplier: Double {
        didSet { UserDefaults.standard.set(speedMultiplier, forKey: "speedMultiplier") }
    }
    @Published var friction: Double {
        didSet { UserDefaults.standard.set(friction, forKey: "friction") }
    }
    @Published var maxVelocity: Double {
        didSet { UserDefaults.standard.set(maxVelocity, forKey: "maxVelocity") }
    }
    @Published var flickSensitivity: Double {
        didSet { UserDefaults.standard.set(flickSensitivity, forKey: "flickSensitivity") }
    }
    
    @Published var enabledDevices: [DeviceInfo] {
        didSet {
            if let data = try? JSONEncoder().encode(enabledDevices) {
                UserDefaults.standard.set(data, forKey: "enabledDevices")
            }
        }
    }
    
    @Published var hasLaunchedBefore: Bool {
        didSet { UserDefaults.standard.set(hasLaunchedBefore, forKey: "hasLaunchedBefore") }
    }
    
    // Global Shortcut Settings
    @Published var isGlobalShortcutEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isGlobalShortcutEnabled, forKey: "isGlobalShortcutEnabled")
            HotKeyManager.shared.update(enabled: isGlobalShortcutEnabled, keyCode: globalShortcutKeyCode, modifiers: globalShortcutModifiers)
        }
    }
    
    @Published var globalShortcutKeyCode: Int {
        didSet {
            UserDefaults.standard.set(globalShortcutKeyCode, forKey: "globalShortcutKeyCode")
            HotKeyManager.shared.update(enabled: isGlobalShortcutEnabled, keyCode: globalShortcutKeyCode, modifiers: globalShortcutModifiers)
        }
    }
    
    @Published var globalShortcutModifiers: Int {
        didSet {
            UserDefaults.standard.set(globalShortcutModifiers, forKey: "globalShortcutModifiers")
            HotKeyManager.shared.update(enabled: isGlobalShortcutEnabled, keyCode: globalShortcutKeyCode, modifiers: globalShortcutModifiers)
        }
    }
    
    // Future proofing
    @Published var precisionEnabled: Bool = false
    
    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "isEnabled")
        
        // Defaults
        let savedSpeed = UserDefaults.standard.double(forKey: "speedMultiplier")
        self.speedMultiplier = savedSpeed == 0 ? 1.5 : savedSpeed
        
        let savedFriction = UserDefaults.standard.double(forKey: "friction")
        self.friction = savedFriction == 0 ? 0.92 : savedFriction
        
        let savedMax = UserDefaults.standard.double(forKey: "maxVelocity")
        self.maxVelocity = savedMax == 0 ? 50.0 : savedMax
        
        let savedSensitivity = UserDefaults.standard.double(forKey: "flickSensitivity")
        self.flickSensitivity = savedSensitivity == 0 ? 3.0 : savedSensitivity
        
        if let data = UserDefaults.standard.data(forKey: "enabledDevices"),
           let devices = try? JSONDecoder().decode([DeviceInfo].self, from: data) {
            self.enabledDevices = devices
        } else {
            self.enabledDevices = []
        }
        
        self.hasLaunchedBefore = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        
        // Shortcut Defaults
        self.isGlobalShortcutEnabled = UserDefaults.standard.bool(forKey: "isGlobalShortcutEnabled")
        
        let savedKeyCode = UserDefaults.standard.integer(forKey: "globalShortcutKeyCode")
        if UserDefaults.standard.object(forKey: "globalShortcutKeyCode") == nil {
            self.globalShortcutKeyCode = 5 // kVK_ANSI_G
        } else {
            self.globalShortcutKeyCode = savedKeyCode
        }
        
        if UserDefaults.standard.object(forKey: "globalShortcutModifiers") == nil {
            self.globalShortcutModifiers = 4096 // controlKey (Carbon)
        } else {
            self.globalShortcutModifiers = UserDefaults.standard.integer(forKey: "globalShortcutModifiers")
        }
        
        // Setup HotKey Handler
        HotKeyManager.shared.onTrigger = { [weak self] in
            guard let self = self else { return }
            self.isEnabled.toggle()
            
            // Also need to start/stop EventTapManager based on new state
            if self.isEnabled {
                EventTapManager.shared.start()
            } else {
                EventTapManager.shared.stop()
            }
        }
        
        // Initialize HotKey (if enabled)
        HotKeyManager.shared.update(enabled: self.isGlobalShortcutEnabled, keyCode: self.globalShortcutKeyCode, modifiers: self.globalShortcutModifiers)
    }
    
    func resetToDefaults() {
        self.speedMultiplier = 1.5
        self.friction = 0.92
        self.maxVelocity = 50.0
        self.flickSensitivity = 3.0
    }
    
    func toggleDevice(_ device: DeviceInfo) {
        if enabledDevices.contains(device) {
            enabledDevices.removeAll { $0 == device }
        } else {
            enabledDevices.append(device)
        }
    }
}
