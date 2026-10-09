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

/// Observes battery data directly so the menu bar label redraws on every snapshot.
struct MenuBarStatusLabel: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: BatteryModel

    private var charging: Bool {
        let snapshot = model.snapshot
        if snapshot.charging == true { return true }
        if snapshot.externalPower == true && (snapshot.percent ?? 0) < 100 && (snapshot.current ?? 0) > 50 {
            return true
        }
        return false
    }

    private var discharging: Bool { model.snapshot.externalPower == false }

    private var fullyCharged: Bool {
        guard !charging else { return false }
        let snapshot = model.snapshot
        return snapshot.externalPower == true &&
            (snapshot.fullyCharged == true || snapshot.percent == 100)
    }

    private var isDark: Bool {
        if colorScheme == .dark { return true }
        let style = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") ?? ""
        if style.caseInsensitiveCompare("Dark") == .orderedSame {
            return true
        }
        if let match = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
            return match == .darkAqua
        }
        return false
    }

    var body: some View {
        let img = MenuBarIconRenderer.render(
            snapshot: model.snapshot,
            isCharging: charging,
            isDischarging: discharging,
            isFullyCharged: fullyCharged,
            isDark: isDark,
            mode: model.menuBarDisplayMode
        )
        Image(nsImage: img)
            .renderingMode(.original)
            .id("\(model.snapshot.percent ?? -1)-\(charging)-\(discharging)-\(isDark)-\(model.menuBarDisplayMode.rawValue)")
            .help("目前電量 · 滿充容量 · 電池健康度")
            .accessibilityLabel(charging ? "充電中" : (discharging ? "電池放電中" : (fullyCharged ? "電池已充滿，仍連接電源" : "已接電，暫停充電")))
    }
}
