import SwiftUI
import AppKit
import Foundation
import UniformTypeIdentifiers
import ServiceManagement
import Carbon
import IOKit.ps
import WidgetKit
import UserNotifications
import AVFoundation
import EventKit

@MainActor
final class BatteryLoggerAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var launchedAsLoginItem = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        let event = NSAppleEventManager.shared().currentAppleEvent
        launchedAsLoginItem = event?.eventID == kAEOpenApplication &&
            event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Observe all window notifications to handle minimize, close, and show
        NotificationCenter.default.addObserver(self, selector: #selector(updateDockStatus), name: NSWindow.didMiniaturizeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateDockStatus), name: NSWindow.didDeminiaturizeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateDockStatus), name: NSWindow.willCloseNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateDockStatus), name: NSWindow.didBecomeKeyNotification, object: nil)

        if launchedAsLoginItem {
            DispatchQueue.main.async {
                NSApp.windows
                    .filter { $0.isVisible && !($0 is NSPanel) }
                    .forEach { $0.close() }
                NSApp.setActivationPolicy(.accessory)
            }
        } else {
            DispatchQueue.main.async {
                self.updateDockStatus()
            }
        }
        UpdateChecker.shared.checkForUpdates(silent: true)
    }

    @objc func updateDockStatus() {
        // Find visible document windows (not status panels / menu bar popovers)
        let hasVisibleNormalWindow = NSApp.windows.contains { win in
            guard win.isVisible, !(win is NSPanel), win.className != "NSStatusBarWindow" else { return false }
            return !win.isMiniaturized
        }

        if hasVisibleNormalWindow {
            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
            }
        } else {
            if NSApp.activationPolicy() != .accessory {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    static func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let win = NSApp.windows.first(where: { !($0 is NSPanel) && $0.className != "NSStatusBarWindow" && $0 != preferencesWindow }) {
            if win.isMiniaturized {
                win.deminiaturize(nil)
            }
            win.makeKeyAndOrderFront(nil)
        }
    }

    static var preferencesWindow: NSWindow?

    static func showPreferencesWindow(model: BatteryModel) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let win = preferencesWindow {
            if win.isMiniaturized { win.deminiaturize(nil) }
            win.makeKeyAndOrderFront(nil)
            return
        }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "偏好設定"
        win.isReleasedWhenClosed = false
        win.center()
        win.setFrameAutosaveName("BatteryLoggerPreferencesWindow")

        let contentView = NSHostingView(
            rootView: PreferencesSheet(model: model, isStandaloneWindow: true)
        )
        win.contentView = contentView

        preferencesWindow = win
        win.makeKeyAndOrderFront(nil)
    }

    static weak var buddyPanel: NSPanel?

    static func updateBuddyPanelSize(isBubbleVisible: Bool) {
        guard let panel = buddyPanel else { return }
        let targetWidth: CGFloat = isBubbleVisible ? 350 : 80
        let targetHeight: CGFloat = isBubbleVisible ? 220 : 80
        let newX = panel.frame.maxX - targetWidth
        let newY = panel.frame.minY
        if let screen = panel.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            let clampedX = max(visible.minX, min(newX, visible.maxX - targetWidth))
            let clampedY = max(visible.minY, min(newY, visible.maxY - targetHeight))
            panel.setFrame(NSRect(x: clampedX, y: clampedY, width: targetWidth, height: targetHeight), display: true, animate: true)
            return
        }
        panel.setFrame(NSRect(x: newX, y: newY, width: targetWidth, height: targetHeight), display: true, animate: true)
    }

    static func toggleBuddyWindow(model: BatteryModel) {
        if let panel = buddyPanel {
            if panel.isVisible {
                panel.orderOut(nil)
            } else {
                panel.makeKeyAndOrderFront(nil)
            }
            return
        }

        // Create a completely transparent, frameless floating panel (Desktop Pet / Buddy)
        // Starts compact (80x80) showing just the sprite
        let panel = NSPanel(
            contentRect: NSRect(x: 100, y: 100, width: 80, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hosting = NSHostingView(rootView: FloatingBuddyView(model: model))
        panel.contentView = hosting

        // Position in bottom-right corner or restored saved position
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let savedX = UserDefaults.standard.double(forKey: "buddy_pos_x")
            let savedY = UserDefaults.standard.double(forKey: "buddy_pos_y")
            if savedX > 0 && savedY > 0 {
                let clampedX = max(visible.minX, min(CGFloat(savedX), visible.maxX - 80))
                let clampedY = max(visible.minY, min(CGFloat(savedY), visible.maxY - 80))
                panel.setFrameOrigin(NSPoint(x: clampedX, y: clampedY))
            } else {
                panel.setFrameOrigin(NSPoint(x: visible.maxX - 100, y: visible.minY + 60))
            }
        }

        buddyPanel = panel
        panel.makeKeyAndOrderFront(nil)
    }

    static func resetBuddyPosition() {
        guard let panel = buddyPanel, let screen = panel.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let targetX = visible.maxX - 100
        let targetY = visible.minY + 60
        panel.setFrameOrigin(NSPoint(x: targetX, y: targetY))
        UserDefaults.standard.set(Double(targetX), forKey: "buddy_pos_x")
        UserDefaults.standard.set(Double(targetY), forKey: "buddy_pos_y")
    }

    static func hideBuddyWindow() {
        buddyPanel?.orderOut(nil)
    }
}
