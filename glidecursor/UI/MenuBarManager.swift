import Cocoa
import SwiftUI

class MenuBarManager: NSObject {
    var statusItem: NSStatusItem
    var popover: NSPopover
    
    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        
        super.init()
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "cursorarrow.motionlines", accessibilityDescription: "GlideCursor")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        
        popover.contentSize = NSSize(width: 300, height: 450)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: SettingsView())
    }
    
    @objc func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }
    
    func showPopover() {
        if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
