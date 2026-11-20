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
        ScreenshotMode.apply(menuBar: menuBarManager)

        if !settings.hasLaunchedBefore {
            settings.isEnabled = true    // 初回からオン(何も起きないと、試されないまま消されてしまうので)
            showFirstLaunch()
        }

        #if DEBUG
        if ScreenshotMode.isOn, UserDefaults.standard.bool(forKey: "GCDonation"), let path = UserDefaults.standard.string(forKey: "GCShotPath") {
            if UserDefaults.standard.string(forKey: "GCAppearance") == "light" { NSApp.appearance = NSAppearance(named: .aqua) }
            showDonation()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                if let v = self?.donationWindow?.contentView?.superview { ScreenshotMode.save(v, to: path) }
                NSApp.terminate(nil)
            }
            return
        }
        #endif
        settings.launchCount += 1
        if settings.launchCount >= 2 && !settings.donationPromptDismissed && !ScreenshotMode.isOn {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.showDonation() }
        }

        if settings.isEnabled {
            Permissions.requestAccessibilityIfNeeded()
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
            if Permissions.accessibilityGranted { GlideController.shared.retryTapIfNeeded() }
        }
    }

    private var donationWindow: NSWindow?

    func showDonation() {
        let view = DonationView { [weak self] in self?.donationWindow?.close() }
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "GlideCursor"
        let host = NSHostingView(rootView: view)
        window.contentView = host
        window.isReleasedWhenClosed = false
        // 中身の大きさを決めてから、画面の中央に置く
        window.setContentSize(host.fittingSize)
        window.center()
        donationWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
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
        window.title = String(localized: "Welcome to GlideCursor")
        window.contentView = NSHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false
        self.firstLaunchWindow = window

        NSApp.activate(ignoringOtherApps: true)
    }
}
