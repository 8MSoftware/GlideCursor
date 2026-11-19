import AppKit
import ServiceManagement

/// 表示言語。system は OS の設定に従う。変更はアプリの再起動で反映される。
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, ja, en
    var id: String { rawValue }

    static var current: AppLanguage {
        let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        guard let langs = domain?["AppleLanguages"] as? [String], let first = langs.first else { return .system }
        return first.hasPrefix("ja") ? .ja : .en
    }

    /// 保存して再起動する
    func apply() {
        guard self != Self.current else { return }
        switch self {
        case .system: UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case .ja: UserDefaults.standard.set(["ja"], forKey: "AppleLanguages")
        case .en: UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
        AppRelauncher.relaunch()
    }
}

enum AppRelauncher {
    /// 自分が終了してから、もう一度開く（多重起動防止に引っかからないよう少し待つ）
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 0.8; /usr/bin/open \"$0\"", path]
        try? p.run()
        NSApp.terminate(nil)
    }
}

/// ログイン時に開く
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("GlideCursor: launch at login change failed: \(error)")
        }
    }
}
