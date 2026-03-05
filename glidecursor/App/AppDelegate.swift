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
            showFirstLaunch()
        }
        
        // Start Event Tap if enabled
        if SettingsManager.shared.isEnabled {
            EventTapManager.shared.start()
        }
    }
    
    func checkAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if !accessEnabled {
            print("Accessibility not enabled")
        }
    }
    
    func showFirstLaunch() {
        let view = FirstLaunchView { [weak self] in
            self?.firstLaunchWindow?.close()
            SettingsManager.shared.hasLaunchedBefore = true
            self?.menuBarManager?.showPopover()
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
