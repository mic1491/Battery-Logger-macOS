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

@main
struct BatteryLoggerApp: App {
    @NSApplicationDelegateAdaptor(BatteryLoggerAppDelegate.self) private var appDelegate
    @StateObject private var model = BatteryModel()

    var body: some Scene {
        Window("電池耗電記錄器", id: "main") {
            DashboardView()
                .environmentObject(model)
                .frame(minWidth: 640, minHeight: 560)
                .onOpenURL { url in
                    model.handleURL(url)
                }
        }
        .defaultSize(width: 760, height: 680)

        MenuBarExtra {
            MenuBarPanel()
                .environmentObject(model)
        } label: {
            MenuBarStatusLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
