import Foundation
import Combine

final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    private let d = UserDefaults.standard

    static let defaults = (speed: 1.0, glideLength: 0.45, flick: 500.0, maxSpeed: 8000.0)

    @Published var isEnabled: Bool { didSet { d.set(isEnabled, forKey: "isEnabled") } }

    /// 離した瞬間の速度に掛ける倍率
    @Published var speedMultiplier: Double { didSet { d.set(speedMultiplier, forKey: "v2.speedMultiplier") } }
    /// 慣性の長さ（減衰の時定数、秒）
    @Published var glideLength: Double { didSet { d.set(glideLength, forKey: "v2.glideLength") } }
    /// これより遅く離したときは慣性を出さない（px/秒）
    @Published var flickThreshold: Double { didSet { d.set(flickThreshold, forKey: "v2.flickThreshold") } }
    /// 慣性の初速の上限（px/秒）
    @Published var maxSpeed: Double { didSet { d.set(maxSpeed, forKey: "v2.maxSpeed") } }

    /// デバイスごとの有効／無効。キーは GlideDevice.id。未設定ならトラックパッドは有効、マウスは無効。
    @Published private(set) var deviceEnabled: [String: Bool] { didSet { d.set(deviceEnabled, forKey: "v2.deviceEnabled") } }

    /// 慣性を止めたタップがクリックにならないようにする
    @Published var suppressClickOnStop: Bool { didSet { d.set(suppressClickOnStop, forKey: "v2.suppressClickOnStop") } }

    @Published var hasLaunchedBefore: Bool { didSet { d.set(hasLaunchedBefore, forKey: "hasLaunchedBefore") } }

    /// 起動した回数(寄付のお願いを2回目から出すため)
    @Published var launchCount: Int { didSet { d.set(launchCount, forKey: "v2.launchCount") } }
    /// 寄付のお願いで「今後は表示しない」を選んだ
    @Published var donationPromptDismissed: Bool { didSet { d.set(donationPromptDismissed, forKey: "v2.donationPromptDismissed") } }

    // Global Shortcut
    @Published var isGlobalShortcutEnabled: Bool {
        didSet { d.set(isGlobalShortcutEnabled, forKey: "isGlobalShortcutEnabled"); updateHotKey() }
    }
    @Published var globalShortcutKeyCode: Int {
        didSet { d.set(globalShortcutKeyCode, forKey: "globalShortcutKeyCode"); updateHotKey() }
    }
    @Published var globalShortcutModifiers: Int {
        didSet { d.set(globalShortcutModifiers, forKey: "globalShortcutModifiers"); updateHotKey() }
    }

    private init() {
        let d = UserDefaults.standard
        func double(_ key: String, _ def: Double) -> Double { d.object(forKey: key) == nil ? def : d.double(forKey: key) }
        isEnabled = d.bool(forKey: "isEnabled")
        speedMultiplier = double("v2.speedMultiplier", Self.defaults.speed)
        glideLength = double("v2.glideLength", Self.defaults.glideLength)
        flickThreshold = double("v2.flickThreshold", Self.defaults.flick)
        maxSpeed = double("v2.maxSpeed", Self.defaults.maxSpeed)
        deviceEnabled = (d.dictionary(forKey: "v2.deviceEnabled") as? [String: Bool]) ?? [:]
        suppressClickOnStop = d.object(forKey: "v2.suppressClickOnStop") == nil ? true : d.bool(forKey: "v2.suppressClickOnStop")
        hasLaunchedBefore = d.bool(forKey: "hasLaunchedBefore")
        launchCount = d.integer(forKey: "v2.launchCount")
        donationPromptDismissed = d.bool(forKey: "v2.donationPromptDismissed")
        isGlobalShortcutEnabled = d.bool(forKey: "isGlobalShortcutEnabled")
        globalShortcutKeyCode = d.object(forKey: "globalShortcutKeyCode") == nil ? 5 : d.integer(forKey: "globalShortcutKeyCode")       // G
        globalShortcutModifiers = d.object(forKey: "globalShortcutModifiers") == nil ? 4096 : d.integer(forKey: "globalShortcutModifiers") // ⌃

        // 旧版の速度設定は単位が違うので読まない（v2. 付きのキーを使う）

        HotKeyManager.shared.onTrigger = { [weak self] in
            guard let self else { return }
            self.setEnabled(!self.isEnabled)
        }
        updateHotKey()
    }

    func setEnabled(_ on: Bool) {
        isEnabled = on
        if on {
            Permissions.requestAccessibilityIfNeeded()
            GlideController.shared.start()
        } else {
            GlideController.shared.stop()
        }
    }

    func isDeviceEnabled(_ device: GlideDevice) -> Bool {
        deviceEnabled[device.id] ?? (device.kind == .trackpad)
    }

    func setDevice(_ device: GlideDevice, enabled: Bool) {
        deviceEnabled[device.id] = enabled
    }

    func resetToDefaults() {
        speedMultiplier = Self.defaults.speed
        glideLength = Self.defaults.glideLength
        flickThreshold = Self.defaults.flick
        maxSpeed = Self.defaults.maxSpeed
    }

    private func updateHotKey() {
        HotKeyManager.shared.update(enabled: isGlobalShortcutEnabled, keyCode: globalShortcutKeyCode, modifiers: globalShortcutModifiers)
    }
}
