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

/// サイトの説明書用の撮影モード(開発用ビルドだけ)。
///   -GCScreenshot YES             起動したらポップオーバーを開き、デバイス名を一般名にする
///   -GCAppearance dark|light      見た目を固定する
enum ScreenshotMode {
    #if DEBUG
    static let isOn = UserDefaults.standard.bool(forKey: "GCScreenshot")
    static let appearance = UserDefaults.standard.string(forKey: "GCAppearance")
    #else
    static let isOn = false
    static let appearance: String? = nil
    #endif

    static func apply(menuBar: MenuBarManager?) {
        guard isOn else { return }
        let look: NSAppearance? = switch appearance {
        case "dark": NSAppearance(named: .darkAqua)
        case "light": NSAppearance(named: .aqua)
        default: nil
        }
        // ポップオーバーはメニューバーの見た目に従うので、ポップオーバーにも直接かける
        if let look {
            NSApp.appearance = look
            menuBar?.popover.appearance = look
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            NSApp.activate()
            menuBar?.showPopover()
        }
        // -GCShotPath <file.png> を付けたら、開いたポップオーバーを画像に書き出して終了する
        #if DEBUG
        if let path = UserDefaults.standard.string(forKey: "GCShotPath") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                // 中身(背景なし)と、枠ごとの画像(背景の色を取るため)の2枚
                if let content = menuBar?.popover.contentViewController?.view {
                    save(content, to: path)
                    if let frame = content.window?.contentView?.superview { save(frame, to: path + ".frame.png") }
                }
                NSApp.terminate(nil)
            }
        }
        #endif
    }

    /// 自分のウィンドウの中身を、画面の倍率のまま PNG にする(画面収録の許可は要らない)
    private static func save(_ view: NSView, to path: String) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}

extension GlideDevice {
    /// 撮影モードでは、持ち主の名前が入ったデバイス名(例 "Cahier's Magic Mouse 2")を出さない
    var displayName: String {
        guard ScreenshotMode.isOn else { return name }
        switch kind {
        case .trackpad: return "Magic Trackpad"
        case .magicMouse: return "Magic Mouse"
        case .mouse: return "Mouse"
        }
    }
}
