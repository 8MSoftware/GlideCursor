import Cocoa
import SwiftUI
import Combine

class MenuBarManager: NSObject {
    var statusItem: NSStatusItem
    var popover: NSPopover
    // .transient が EventTap 追加後に壊れる場合のバックアップ外クリック検知
    private var outsideClickMonitor: Any?
    private var precisionWatch: AnyCancellable?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()

        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "cursorarrow.motionlines", accessibilityDescription: "GlideCursor")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        // 精密モードのあいだは、アイコンを変える
        precisionWatch = PrecisionMode.shared.$isOn.receive(on: DispatchQueue.main).sink { [weak self] on in
            self?.statusItem.button?.image = NSImage(systemSymbolName: on ? "scope" : "cursorarrow.motionlines",
                                                     accessibilityDescription: "GlideCursor")
        }

        popover.behavior = .transient
        popover.delegate = self
        let host = NSHostingController(rootView: SettingsView())
        host.sizingOptions = .preferredContentSize   // 設定画面の高さに合わせる
        popover.contentViewController = host
    }

    @objc func togglePopover(_ sender: Any?) {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    func showPopover() {
        if let button = statusItem.button {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // グローバルモニタで外クリックを確実に拾う（EventTap 追加後に .transient が壊れる対策）
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.closePopover()
            }
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }
}

extension MenuBarManager: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        // delegate 経由で閉じた場合もモニタを解放
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }
}
