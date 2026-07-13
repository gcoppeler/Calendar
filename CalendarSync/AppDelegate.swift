import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    let syncManager = SyncManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildStatusItem()
        buildPopover()
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        if let image = NSImage(systemSymbolName: "calendar", accessibilityDescription: "CalendarSync") {
            button.image = image
        } else {
            button.title = "📅"
        }
        button.action = #selector(togglePopover(_:))
        button.target = self
    }

    private func buildPopover() {
        let popover = NSPopover()
        popover.contentViewController = NSHostingController(rootView: SyncStatusView(mgr: syncManager))
        popover.behavior = .transient
        self.popover = popover
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        guard let popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
