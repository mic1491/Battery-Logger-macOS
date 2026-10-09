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

struct BatteryDailyHealthRecord: Codable, Identifiable {
    var id: String { date }
    let date: String
    let percent: Int
    let health: Double
    let fullCapacity: Int
    let designCapacity: Int
    let cycles: Int
    let maxMvDiff: Int?
    let temperature: Double?
}

/// An energy-consuming app detected during high discharge spikes.
struct EnergyVampireApp: Identifiable, Sendable {
    let id: Int // pid
    let name: String
    let cpuPercent: Double
    let bundleId: String?
}

/// A calendar meeting or outing alert detected ahead of time.
struct CalendarOutingAlert: Identifiable, Sendable {
    let id: String
    let title: String
    let startTime: Date
    let timeDescription: String
}

/// A report on battery preservation and temperature during sleep.
struct SleepGuardianReport: Codable, Identifiable, Sendable {
    var id: String { date }
    let date: String
    let durationHours: Double
    let drainPercent: Int
    let wakeTemperature: Double
    let isSafe: Bool
    let summary: String
}

/// Native voice prompt and J.A.R.V.I.S. butler speech synthesizer.

struct BatteryImpactAnalysis: Sendable {
    enum Level: Sendable {
        case optimal
        case good
        case warning
        case danger

        var color: Color {
            switch self {
            case .optimal: return .green
            case .good: return .blue
            case .warning: return .orange
            case .danger: return .red
            }
        }

        var icon: String {
            switch self {
            case .optimal: return "shield.lefthalf.filled"
            case .good: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .danger: return "flame.fill"
            }
        }

        var tagText: String {
            switch self {
            case .optimal: return "黃金保養"
            case .good: return "良好狀態"
            case .warning: return "需注意"
            case .danger: return "損害風險"
            }
        }
    }

    var level: Level
    var title: String
    var description: String
    var suggestion: String
    var cellVoltageEstimate: String
}

struct BatterySnapshot: Sendable {
    var model: String = "讀取中…"
    var processor: String = "—"
    var memory: String = "—"
    var macOS: String = "—"
    var build: String = "—"
    var uptime: String = "—"
    var percent: Int?
    var capacity: Int?
    var fullCapacity: Int?
    var designCapacity: Int?
    var voltage: Int?
    var current: Int?
    var cycles: Int?
    var temperature: Double?
    var cpuTemperature: Double?
    var manufacturer: String = "—"
    var controllerModel: String = "—"
    var timeRemaining: Int?
    var fullyCharged: Bool?
    var maxError: Int?
    var externalChargeCapable: Bool?
    var condition: String = "—"
    var externalPower: Bool?
    var charging: Bool?
    var chargeLimit: Int? = 100
    var cellVoltages: [Int] = []
    var qmax: [Int] = []
    var serialNumber: String = "—"
    var permanentFailureStatus: Int? = 0
    var adapterWatts: Int?
    var adapterVoltageMv: Int?
    var adapterCurrentMa: Int?
    var adapterDescription: String?
    var updated = Date()

    /// Cell imbalance in millivolts (max voltage - min voltage)
    var cellImbalanceMv: Int? {
        guard !cellVoltages.isEmpty else { return nil }
        guard let maxV = cellVoltages.max(), let minV = cellVoltages.min() else { return nil }
        return maxV - minV
    }

    /// Cell balance condition text
    var cellBalanceText: String {
        guard let diff = cellImbalanceMv else { return "系統未提供各電芯讀值" }
        if diff <= 25 {
            return "極佳（壓差 \(diff) mV · 各芯電壓極度均衡）"
        } else if diff <= 55 {
            return "正常良好（壓差 \(diff) mV · 處於正常化學公差）"
        } else {
            return "注意（壓差 \(diff) mV · 電芯老化衰減不均）"
        }
    }

    enum SwellRiskLevel {
        case minimal
        case mild
        case severeWarning

        var title: String {
            switch self {
            case .minimal: return "微小（電芯化學一致性極高）"
            case .mild: return "輕微偏差（日常輕度化學漂移）"
            case .severeWarning: return "⚠️ 局部微膨脹 / 劣化高風險"
            }
        }

        var color: Color {
            switch self {
            case .minimal: return .green
            case .mild: return .yellow
            case .severeWarning: return .red
            }
        }
    }

    var cellSwellRisk: (level: SwellRiskLevel, tip: String)? {
        guard let diff = cellImbalanceMv else { return nil }
        if diff < 20 {
            return (.minimal, "各電芯內阻與開路電壓非常接近，完全無局部過充微鼓包跡象。")
        } else if diff < 55 {
            return (.mild, "電芯出現輕微阻抗差異，屬一般老化公差；建議避免高負載邊跑邊快充。")
        } else {
            return (.severeWarning, "電芯壓差已超過 55mV！通常為某顆電芯內阻驟升或微量產氣前兆。請定期檢查筆電底蓋與觸控板是否平整，避免長時間 100% 待機！")
        }
    }

    enum CableGrade {
        case excellent
        case good
        case fair
        case warningPoor

        var title: String {
            switch self {
            case .excellent: return "旗艦滿血（極低損耗）"
            case .good: return "原廠標準（傳輸良好）"
            case .fair: return "普通通用（輕微壓降）"
            case .warningPoor: return "高阻抗老化（發熱風險）"
            }
        }

        var color: Color {
            switch self {
            case .excellent: return .green
            case .good: return .blue
            case .fair: return .orange
            case .warningPoor: return .red
            }
        }
    }

    struct CableHealthAnalysis {
        let inputWatts: Double
        let outputWatts: Double
        let lossWatts: Double
        let lossPercent: Double
        let grade: CableGrade
        let advice: String
    }

    var cableHealthAnalysis: CableHealthAnalysis? {
        guard externalPower == true, let inV = adapterVoltageMv, let inMa = adapterCurrentMa, inMa > 300 else { return nil }
        let inW = Double(inV) * Double(inMa) / 1_000_000.0
        guard inW > 5.0 else { return nil }
        let outW = chargeWatts ?? (inW * 0.94)
        let loss = max(0.2, inW - outW)
        let lossPct = min(40.0, max(1.0, (loss / inW) * 100.0))

        let grade: CableGrade
        let advice: String
        if lossPct <= 6.0 {
            grade = .excellent
            advice = "線材與接頭導通良好，接觸電阻極低，幾無額外傳輸發熱。"
        } else if lossPct <= 12.0 {
            grade = .good
            advice = "標準 USB-PD 握手供電，正常轉化損耗。"
        } else if lossPct <= 18.0 {
            grade = .fair
            advice = "線材損耗略高，可能是線身長度較長（2M+）或接頭稍有微塵氧化。"
        } else {
            grade = .warningPoor
            advice = "⚠️ 傳輸損耗與壓降偏高（約 \(String(format: "%.1f", lossPct))%），接頭與線材可能存在老化氧化或高阻抗，建議留意線頭溫度或更換高品質線材。"
        }

        return CableHealthAnalysis(
            inputWatts: inW,
            outputWatts: outW,
            lossWatts: loss,
            lossPercent: lossPct,
            grade: grade,
            advice: advice
        )
    }

    enum MagSafeLedState {
        case amber(String)
        case green(String)
        case off(String)

        var color: Color {
            switch self {
            case .amber: return .orange
            case .green: return .green
            case .off: return .secondary
            }
        }

        var title: String {
            switch self {
            case .amber(let t): return t
            case .green(let t): return t
            case .off(let t): return t
            }
        }
    }

    var magSafeLedState: MagSafeLedState {
        guard externalPower == true else { return .off("未連接供電") }
        if charging == true {
            return .amber("MagSafe 快充中 (橘燈)")
        } else {
            return .green("MagSafe 旁路供電保護 (綠燈)")
        }
    }

    /// User-friendly explanation of cycle count lifecycle stage
    var cycleStageExplanation: String {
        guard let cycles else { return "循環數未提供" }
        if cycles < 100 {
            return "\(cycles) 次 · 全新品質期（< 100 次，電芯衰退可忽略）"
        } else if cycles < 300 {
            return "\(cycles) 次 · 黃金青年期（100-300 次，容量保持在 90%+）"
        } else if cycles < 600 {
            return "\(cycles) 次 · 穩健中年期（300-600 次，典型日常使用水準）"
        } else if cycles < 800 {
            return "\(cycles) 次 · 成熟後期（600-800 次，電芯阻抗漸增，容量約 80%）"
        } else if cycles < 1000 {
            return "\(cycles) 次 · 臨界設計期（800-1000 次，接近原廠 1000 次基準）"
        } else {
            return "\(cycles) 次 · 超額服役（> 1000 次，建議隨時注意蓄電力）"
        }
    }

    /// Signed battery-side power: positive while charging, negative while discharging.
    var batteryPowerWatts: Double? {
        guard let current, let voltage else { return nil }
        return Double(current) * Double(voltage) / 1_000_000
    }

    var dischargeWatts: Double? {
        guard let watts = batteryPowerWatts, watts < 0 else { return nil }
        return -watts
    }

    var chargeWatts: Double? {
        guard charging == true, let watts = batteryPowerWatts, watts > 0 else { return nil }
        return watts
    }

    var batterySymbol: String {
        if charging == true { return "bolt.fill" }
        guard let percent else { return "battery.0" }
        switch max(0, min(percent, 100)) {
        case 0: return "battery.0"
        case 1...25: return "battery.25"
        case 26...50: return "battery.50"
        case 51...75: return "battery.75"
        default: return "battery.100"
        }
    }

    var batteryIconColor: Color {
        if charging == true { return .green }
        guard let percent else { return .secondary }
        if percent <= 20 { return .red }
        if percent <= 35 { return .orange }
        return .accentColor
    }

    var powerStatusText: String {
        if externalPower == true && (fullyCharged == true || percent == 100) {
            return "電源轉接器為來源，電池已充滿"
        }
        if externalPower == true && charging == true {
            return "電源轉接器為來源，電池正在充電"
        }
        if externalPower == true {
            return "電源轉接器為來源，電池未充電／暫停充電"
        }
        if externalPower == false {
            return "電池為來源，正在放電"
        }
        return charging == true ? "電池正在充電" : "電源狀態未知"
    }

    var healthPercent: Double? {
        guard let fullCapacity, let designCapacity, designCapacity > 0 else { return nil }
        return Double(fullCapacity) / Double(designCapacity) * 100
    }

    /// Charger & Cable Quality Rating
    var chargerRatingText: String {
        guard externalPower == true else { return "未連接充電器（純電池供電）" }
        guard let watts = adapterWatts else { return "已接電源（通用充電器）" }
        if watts >= 140 {
            return "⚡️⚡️ 旗艦極速快充（140W USB-PD 3.1 協議）"
        } else if watts >= 90 {
            return "⚡️ 高速快充（\(watts)W USB-PD 滿血協議）"
        } else if watts >= 60 {
            return "⚡️ 標準快充（\(watts)W 原廠標準供電）"
        } else if watts >= 30 {
            return "🔹 輕量補電（\(watts)W 輕巧型充電器）"
        } else {
            return "⚠️ 慢速供電（僅 \(watts)W，線材或充電頭效率較低）"
        }
    }

    /// Estimated time to reach the hardware charge limit (e.g. 80%, 85%, 90%)
    func timeToReachLimit(limit: Int?) -> (minutes: Int, text: String)? {
        guard charging == true, let current, current > 100, let pct = percent, let full = fullCapacity else { return nil }
        let target = limit ?? 85
        guard pct < target else { return (0, "已達上限") }
        let neededMah = Double(target - pct) / 100.0 * Double(full)
        let hours = neededMah / Double(current)
        let totalMinutes = Int(hours * 60)
        if totalMinutes < 60 {
            return (totalMinutes, "\(totalMinutes) 分鐘")
        } else {
            return (totalMinutes, "\(totalMinutes / 60) 小時 \(totalMinutes % 60) 分")
        }
    }

    /// Estimated remaining years of healthy battery service (until 80% SOH)
    var estimatedRemainingYears: Double? {
        guard let health = healthPercent, let cycles, cycles > 10 else { return nil }
        let wearSoFar = max(0.5, 100.0 - health)
        let wearPerCycle = wearSoFar / Double(cycles)
        let remainingHealthDrop = max(0.1, health - 80.0)
        let remainingCycles = remainingHealthDrop / wearPerCycle
        let avgCyclesPerYear = 140.0 // Typical daily laptop usage
        return max(0.5, remainingCycles / avgCyclesPerYear)
    }

    /// Second-hand value preservation estimation
    var resaleValuePreservationText: String {
        guard let health = healthPercent else { return "評估中" }
        if health >= 90 {
            return "優異（健康度 \(String(format: "%.1f", health))% · 二手殘值推估多保留約 NT$ 2,000 ~ 2,800 元）"
        } else if health >= 82 {
            return "良好（健康度 \(String(format: "%.1f", health))% · 二手殘值推估多保留約 NT$ 1,000 ~ 1,500 元）"
        } else {
            return "一般（建議維持 85% 上限以防急速老化）"
        }
    }

    var replacementAdvice: String {
        let status = condition.lowercased()
        if status.contains("service") || status.contains("replace") || status.contains("repair") || condition.contains("維修") || condition.contains("更換") {
            return "macOS 已回報「\(condition)」。建議安排 Apple 或授權維修中心檢測，並依診斷結果更換電池。"
        }
        if let cycles, cycles >= 1000 {
            return "已達 MacBook Pro 2020 電池約 1,000 次的循環設計上限。循環數不是故障判定；建議安排檢測，若續航已影響使用就更換。"
        }
        if let healthPercent, healthPercent < 80 {
            return String(format: "app 依滿充容量／設計容量估算為 %.1f%%，低於 80%%；但 macOS 健康狀態目前是「%@」。這是容量估算，不等同 Apple 診斷。若續航明顯縮短、突然關機或 macOS 顯示建議維修，再安排更換；目前可先監測。", healthPercent, condition)
        }
        return "目前沒有明確的更換訊號。以 macOS 電池健康狀態為主；若顯示建議維修、續航明顯縮短或發生突然關機，再安排檢測或更換。"
    }

    var replacementAdviceIcon: String {
        if condition.lowercased().contains("service") || condition.lowercased().contains("replace") || condition.contains("維修") || condition.contains("更換") { return "exclamationmark.triangle.fill" }
        if let cycles, cycles >= 1000 { return "exclamationmark.triangle.fill" }
        if let healthPercent, healthPercent < 80 { return "info.circle.fill" }
        return "checkmark.circle.fill"
    }

    var impactAnalysis: BatteryImpactAnalysis {
        let temp = temperature ?? 25.0
        let pct = percent ?? 50
        let isPlugged = externalPower == true
        let isChg = charging == true
        let limit = chargeLimit ?? 100

        if temp >= 36.0 {
            return BatteryImpactAnalysis(
                level: .danger,
                title: "電池溫度偏高（\(String(format: "%.1f", temp)) °C）",
                description: "高溫是加速鋰電池電解液氧化分解、產氣膨脹與容量暴跌的頭號元兇。在 35°C 以上的高溫環境持續充電，副反應速率呈指數級上升。",
                suggestion: "建議暫停高負載作業、移至通風處降溫，或避免邊跑高耗能邊高速充電。",
                cellVoltageEstimate: isChg ? "~4.15V - 4.25V（高溫加壓中）" : "~3.95V - 4.05V"
            )
        }

        if pct < 20 {
            return BatteryImpactAnalysis(
                level: .warning,
                title: "電量過低（< 20% 深度過放區）",
                description: "電量低於 20% 時單芯電壓掉入低壓陡坡（< 3.75V），電芯內部阻抗急遽升高。頻繁或長時間處於過放狀態容易造成負極銅箔微量溶解與不可逆損耗。",
                suggestion: "建議儘速連接充電器補電，日常盡可能維持在 20% 以上以延長循環壽命。",
                cellVoltageEstimate: "< 3.75V（低壓臨界）"
            )
        }

        if isPlugged && limit <= 90 && pct >= limit - 2 {
            return BatteryImpactAnalysis(
                level: .optimal,
                title: "黃金保養中（硬體已限制在 \(limit)%）",
                description: "目前電量維持在 \(limit)% 安全保養區間，電芯電壓處於 ~4.0V 甜蜜點，有效阻斷電解液於 4.2V+ 極限高壓下的氧化分解，日曆衰退速度降低約 60%。",
                suggestion: "非常適合長時間外接螢幕或插電工作，能大幅預防電池發熱鼓包。外出前可隨時點擊「100% 解鎖」。",
                cellVoltageEstimate: "~3.98V - 4.05V（理想安全電壓）"
            )
        }

        if isPlugged && (pct == 100 || fullyCharged == true) {
            return BatteryImpactAnalysis(
                level: .warning,
                title: "處於 100% 極限高壓待機狀態",
                description: "電池維持在 4.25V～4.35V 最高截止電壓。若長期維持滿電且筆電伴隨工作溫度，將對正極晶格與電解液造成最大的日曆老化應力。",
                suggestion: "若為常駐插電辦公，強烈建議設定 85% 或 90% 充電上限；此舉可將整體使用壽命延長 2～3 倍。",
                cellVoltageEstimate: "~4.25V - 4.35V（極限高應力區）"
            )
        }

        if isPlugged && isChg && pct >= 85 {
            return BatteryImpactAnalysis(
                level: .warning,
                title: "高壓加壓充電中（\(pct)%）",
                description: "目前電量已超過 85%，充電電壓接近最高峰值。最後 15% 的充電是電池承受電化學應力最大的階段。",
                suggestion: "若今日無長時間離線外出需求，建議設定 85% / 90% 限制，停止繼續推向 100%。",
                cellVoltageEstimate: "~4.15V - 4.25V（高壓充填中）"
            )
        }

        if isPlugged && isChg {
            return BatteryImpactAnalysis(
                level: .good,
                title: "正常充電中（\(pct)%）",
                description: "目前處於中段恆流充電區間，電壓平穩上升，屬於鋰電池能效最高的充電階段。",
                suggestion: "達到 85% 或 90% 時系統將依您的設定自動保養或提醒。",
                cellVoltageEstimate: "~3.85V - 4.10V（健康爬升）"
            )
        }

        if !isPlugged {
            return BatteryImpactAnalysis(
                level: .optimal,
                title: "最佳放電循環區間（\(pct)%）",
                description: "目前處於 20%～85% 最佳循環窗口，無高壓氧化亦無過放損耗，為鋰電池最舒適的工作狀態。",
                suggestion: "可正常使用，電量接近 20% 前及時補電即可維持最佳循環壽命。",
                cellVoltageEstimate: "~3.80V - 4.00V（健康工作電壓）"
            )
        }

        return BatteryImpactAnalysis(
            level: .good,
            title: "電源狀態良好（\(pct)%）",
            description: "電池工作在正常電壓與溫度範圍內。",
            suggestion: "維持 20%～85% 的充放電習慣，能有效延長電池壽命。",
            cellVoltageEstimate: "~3.90V"
        )
    }
}

struct SystemDetails: Sendable {
    var model = "—"
    var processor = "—"
    var memory = "—"
    var macOS = "—"
    var build = "—"
    var condition = "—"
}

struct LogSummary {
    let path: String
    let model: String
    let macOS: String
    let start: Date
    let end: Date
    let startPercent: Int?
    let endPercent: Int?
    let startCapacity: Int?
    let endCapacity: Int?
    let awakeWh: Double?
    let sleepSeconds: TimeInterval
}

struct BatteryCompatibility: Sendable {
    let machineModel: String
    let batteryModel: String
    let capacity: String
    let sourceTitle: String
    let sourceURL: String

    static let catalog: [String: BatteryCompatibility] = [
        "MacBookPro16,2": BatteryCompatibility(machineModel: "A2251 · 13 吋 2020，四個 Thunderbolt 埠", batteryModel: "A1964", capacity: "5086 mAh · 58 Wh · 11.41 V", sourceTitle: "iFixit 相容機型與電池規格", sourceURL: "https://www.ifixit.com/products/macbook-pro-13-retina-mid-a1989-a2251-battery"),
        "MacBookPro16,3": BatteryCompatibility(machineModel: "A2289 · 13 吋 2020，兩個 Thunderbolt 埠", batteryModel: "A2171", capacity: "5100 mAh · 58.2 Wh · 11.41 V", sourceTitle: "iFixit 相容機型與電池規格", sourceURL: "https://www.ifixit.com/products/macbook-pro-13-retina-mid-2019-battery"),
        "MacBookPro17,1": BatteryCompatibility(machineModel: "A2338 · 13 吋 M1 2020", batteryModel: "A2171", capacity: "5100 mAh · 58.2 Wh · 11.41 V", sourceTitle: "iFixit 相容機型與電池規格", sourceURL: "https://www.ifixit.com/products/macbook-pro-13-retina-mid-2019-battery"),
        "Mac14,7": BatteryCompatibility(machineModel: "A2338 · 13 吋 M2 2022", batteryModel: "A2171", capacity: "5100 mAh · 58.2 Wh · 11.41 V", sourceTitle: "iFixit 相容機型與電池規格", sourceURL: "https://www.ifixit.com/products/macbook-pro-13-retina-mid-2019-battery"),
        "MacBookPro16,1": BatteryCompatibility(machineModel: "A2141 · 16 吋 2019", batteryModel: "A2113", capacity: "8790 mAh · 98.8 Wh · 11.36 V", sourceTitle: "iFixit 相容機型與電池規格", sourceURL: "https://www.ifixit.com/products/macbook-pro-16-2019-battery"),
        "MacBookPro16,4": BatteryCompatibility(machineModel: "A2141 · 16 吋 2019", batteryModel: "A2113", capacity: "8790 mAh · 98.8 Wh · 11.36 V", sourceTitle: "iFixit 相容機型與電池規格", sourceURL: "https://www.ifixit.com/products/macbook-pro-16-2019-battery"),
        "MacBookPro15,2": BatteryCompatibility(machineModel: "A1989 · 13 吋 2018–2019，四個 Thunderbolt 埠", batteryModel: "A1964", capacity: "5086 mAh · 58 Wh · 11.41 V", sourceTitle: "iFixit 相容機型與電池規格", sourceURL: "https://www.ifixit.com/products/macbook-pro-13-retina-mid-a1989-a2251-battery"),
        "MacBookPro15,4": BatteryCompatibility(machineModel: "A2159 · 13 吋 2019，兩個 Thunderbolt 埠", batteryModel: "A2171", capacity: "5100 mAh · 58.2 Wh · 11.41 V", sourceTitle: "iFixit 相容機型與電池規格", sourceURL: "https://www.ifixit.com/products/macbook-pro-13-retina-mid-2019-battery"),
        "MacBookAir9,1": BatteryCompatibility(machineModel: "A2179 · 13 吋 Intel 2020", batteryModel: "A1965", capacity: "4379 mAh · 49.9 Wh · 11.4 V", sourceTitle: "iFixit 相容機型與電池規格", sourceURL: "https://www.ifixit.com/products/macbook-air-13-late-2018-early-2020-battery"),
        "MacBookAir10,1": BatteryCompatibility(machineModel: "A2337 · 13 吋 M1 2020", batteryModel: "A2389", capacity: "4380 mAh · 49.9 Wh · 11.39 V", sourceTitle: "iFixit 相容機型與電池規格", sourceURL: "https://www.ifixit.com/products/macbook-air-13-a2337-late-2020-battery")
    ]
}

