import Carbon
import AppKit

// Global C-function for the event handler
private func hotKeyHandler(nextHandler: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    HotKeyManager.shared.handleTrigger()
    return noErr
}

class HotKeyManager {
    static let shared = HotKeyManager()
    private var hotKeyRef: EventHotKeyRef?
    
    var onTrigger: (() -> Void)?
    
    private init() {
        // Install the event handler for the hotkey event
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &eventType, nil, nil)
    }
    
    func handleTrigger() {
        DispatchQueue.main.async {
            self.onTrigger?()
        }
    }
    
    func update(enabled: Bool, keyCode: Int, modifiers: Int) {
        unregister()
        
        if enabled {
            // Default to Control + G if 0 (though SettingsManager should handle defaults)
            let kCode = UInt32(keyCode)
            let mods = UInt32(modifiers)
            
            let hotKeyID = EventHotKeyID(signature: OSType(0x474C4944), id: 1) // 'GLID'
            
            let status = RegisterEventHotKey(kCode, mods, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
            if status != noErr {
                print("Failed to register hotkey: \(status)")
            }
        }
    }
    
    private func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
}
