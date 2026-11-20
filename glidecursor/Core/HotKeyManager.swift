import Carbon
import AppKit

/// グローバルショートカット(Carbon の RegisterEventHotKey)。
/// 1: GlideCursor のオン・オフ、2: 精密モードの切り替え
private func hotKeyHandler(nextHandler: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    var hk = EventHotKeyID()
    if let event {
        GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                          nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
    }
    HotKeyManager.shared.handleTrigger(id: hk.id)
    return noErr
}

final class HotKeyManager {
    static let shared = HotKeyManager()

    enum Key: UInt32 { case toggle = 1, precision = 2 }

    private var refs: [Key: EventHotKeyRef] = [:]
    var onTrigger: (() -> Void)?
    var onPrecision: (() -> Void)?

    private init() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &eventType, nil, nil)
    }

    func handleTrigger(id: UInt32) {
        DispatchQueue.main.async {
            switch Key(rawValue: id) {
            case .precision: self.onPrecision?()
            default: self.onTrigger?()
            }
        }
    }

    /// 1つ目(オン・オフ)。旧来の呼び方
    func update(enabled: Bool, keyCode: Int, modifiers: Int) {
        update(.toggle, enabled: enabled, keyCode: keyCode, modifiers: modifiers)
    }

    func update(_ key: Key, enabled: Bool, keyCode: Int, modifiers: Int) {
        if let ref = refs.removeValue(forKey: key) { UnregisterEventHotKey(ref) }
        guard enabled else { return }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x474C4944), id: key.rawValue) // 'GLID'
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { refs[key] = ref } else { NSLog("GlideCursor: hotkey \(key) failed: \(status)") }
    }
}
