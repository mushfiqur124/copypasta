//
//  Copy_PastaApp.swift
//  Copy Pasta
//
//  Created by Mushfiqur Rahman on 2025-05-03.
//

import SwiftUI

@main
struct Copy_PastaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var eventMonitor: EventMonitor?
    private var statusBarMenu: NSMenu?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the status item in the menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let statusButton = statusItem?.button {
            statusButton.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Copy Pasta")
            statusButton.target = self
            statusButton.action = #selector(statusBarButtonClicked(_:))
            
            // Create the status bar menu
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Quit Copy Pasta", 
                                  action: #selector(NSApplication.terminate(_:)), 
                                  keyEquivalent: "q"))
            self.statusBarMenu = menu
            
            // Enable right-click detection
            statusButton.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        // Create and configure the popover
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 400)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ClipboardListView())
        popover.delegate = self
        self.popover = popover
        
        // Create event monitor to detect clicks outside the popover
        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let popover = self.popover else { return }
            
            if popover.isShown {
                // Close the popover when clicking outside
                self.closePopover(event)
            }
        }
        eventMonitor?.start()
    }
    
    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!
        
        if event.type == .rightMouseUp {
            // Show menu on right click
            statusBarMenu?.popUp(positioning: nil, 
                               at: NSPoint(x: 0, y: sender.bounds.height), 
                               in: sender)
        } else {
            // Toggle popover on left click
            if let popover = self.popover {
                if popover.isShown {
                    closePopover(sender)
                } else {
                    showPopover(sender)
                }
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Clean up event monitor
        eventMonitor?.stop()
    }
    
    func showPopover(_ sender: NSView) {
        if let popover = self.popover {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            eventMonitor?.start()
        }
    }
    
    func closePopover(_ sender: Any?) {
        popover?.performClose(sender)
    }
    
    // Popover delegate method
    func popoverWillClose(_ notification: Notification) {
        // Ensure event monitor is stopped when popover closes
        eventMonitor?.stop()
    }
}

// Event monitor to detect clicks outside the popover
class EventMonitor {
    private var monitor: Any?
    private let mask: NSEvent.EventTypeMask
    private let handler: (NSEvent?) -> Void
    
    init(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent?) -> Void) {
        self.mask = mask
        self.handler = handler
    }
    
    deinit {
        stop()
    }
    
    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
    }
    
    func stop() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
