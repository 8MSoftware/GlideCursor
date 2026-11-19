import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarManager: MenuBarManager?
    var firstLaunchWindow: NSWindow?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 多重起動防止: 同一 bundle ID のプロセスが既に存在すれば前面化して即終了
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty {
            others.first?.activate(options: .activateIgnoringOtherApps)
            NSApp.terminate(nil)
            return
        }

        let settings = SettingsManager.shared
        _ = DeviceRegistry.shared
        menuBarManager = MenuBarManager()

        if !settings.hasLaunchedBefore {
            settings.isEnabled = false   // 初回は必ず OFF
            showFirstLaunch()
        }

        if settings.isEnabled {
            GlideController.shared.start()
        }
        watchAccessibility()

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(handleWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(handleDidWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc func handleWillSleep(_ notification: Notification) {
        InertiaEngine.shared.stop()
    }

    @objc func handleDidWake(_ notification: Notification) {
        // スリープ後は MT デバイスからフレームが届かなくなることがあるので取り直す
        GlideController.shared.refreshDevices()
    }

    /// アクセシビリティ権限が後から与えられたら、イベントタップを作り直す
    private func watchAccessibility() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            if AXIsProcessTrusted() { GlideController.shared.retryTapIfNeeded() }
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
