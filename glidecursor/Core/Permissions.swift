import AppKit
import ApplicationServices

enum Permissions {
    static var accessibilityGranted: Bool { AXIsProcessTrusted() }

    /// 未許可なら、システムの許可ダイアログを出して一覧に GlideCursor を載せる
    static func requestAccessibilityIfNeeded() {
        guard !accessibilityGranted else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
