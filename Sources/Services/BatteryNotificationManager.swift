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

/// Central manager for user-facing macOS banner notifications.
@MainActor
final class BatteryNotificationManager {
    static let shared = BatteryNotificationManager()
    private var lastNotifiedLimit: Int?
    private var lastNotifiedHighTemp: Bool = false
    private var lastNotifiedLowBattery: Bool = false

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func checkAndNotify(snapshot: BatterySnapshot, limit: Int?, enabled: Bool, onLimit: Bool, onTemp: Bool, onLow: Bool) {
        guard enabled else { return }
        let center = UNUserNotificationCenter.current()

        // 1. Charge limit reached
        if onLimit, let limit, let pct = snapshot.percent, snapshot.externalPower == true {
            if pct >= limit && lastNotifiedLimit != limit {
                lastNotifiedLimit = limit
                let content = UNMutableNotificationContent()
                content.title = "⚡️ 已達充電上限（\(limit)%）"
                content.body = "Mac 目前電量已達保護上限 \(limit)%，系統已自動限制充電以保護電芯壽命。"
                content.sound = .default
                let req = UNNotificationRequest(identifier: "limit_reached_\(limit)", content: content, trigger: nil)
                center.add(req)
            } else if pct < limit - 3 {
                lastNotifiedLimit = nil
            }
        }

        // 2. High temperature warning
        if onTemp, let temp = snapshot.temperature {
            if temp >= 37.0 && !lastNotifiedHighTemp {
                lastNotifiedHighTemp = true
                let content = UNMutableNotificationContent()
                content.title = "🔥 電池溫度偏高警報（\(String(format: "%.1f", temp))°C）"
                content.body = "高溫會加速鋰電池老化與電解液分解，建議暫停重負載運算或將 Mac 移至通風處降溫。"
                content.sound = .defaultCritical
                let req = UNNotificationRequest(identifier: "temp_high", content: content, trigger: nil)
                center.add(req)
            } else if temp <= 34.0 {
                lastNotifiedHighTemp = false
            }
        }

        // 3. Low battery warning
        if onLow, let pct = snapshot.percent, snapshot.externalPower == false {
            if pct <= 20 && !lastNotifiedLowBattery {
                lastNotifiedLowBattery = true
                let content = UNMutableNotificationContent()
                content.title = "🪫 電池電量過低（\(pct)%）"
                content.body = "電量已進入 20% 深度放電陡坡，建議儘速連接電源供應器以延長電池循環壽命。"
                content.sound = .default
                let req = UNNotificationRequest(identifier: "low_battery", content: content, trigger: nil)
                center.add(req)
            } else if pct > 25 || snapshot.externalPower == true {
                lastNotifiedLowBattery = false
            }
        }
    }
}
