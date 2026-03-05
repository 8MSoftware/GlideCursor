import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarManager: MenuBarManager?
    var firstLaunchWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check Accessibility Permissions
        checkAccessibility()
        
        // Initialize Managers
        _ = SettingsManager.shared
        _ = EventTapManager.shared
        
        // Setup Menu Bar
        menuBarManager = MenuBarManager()
        
        // Check First Launch
        if !SettingsManager.shared.hasLaunchedBefore {
            // 初回は必ず OFF にする（前回テスト等で true が残っていても上書き）
            SettingsManager.shared.isEnabled = false
            showFirstLaunch()
        }
        
        // Start Event Tap if enabled
        if SettingsManager.shared.isEnabled {
            EventTapManager.shared.start()
        }
    }
    
    func checkAccessibility() {
        // prompt: false = 権限状態を確認するだけでOSダイアログは出さない
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)

        if !accessEnabled {
            print("Accessibility not enabled")
        }
    }
    
    func showFirstLaunch() {
        let view = FirstLaunchView { [weak self] in
            SettingsManager.shared.hasLaunchedBefore = true
            self?.menuBarManager?.showPopover()   // アプリがアクティブな間に popover を開く
            DispatchQueue.main.async {
                self?.firstLaunchWindow?.close()  // popover 表示後に window を閉じる
            }
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.center()
        window.title = "Welcome to GlideCursor"
        window.contentView = NSHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false
        self.firstLaunchWindow = window
        
        NSApp.activate(ignoringOtherApps: true)
    }
}
