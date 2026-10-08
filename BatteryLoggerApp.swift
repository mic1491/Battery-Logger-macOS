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

typealias FileManager = Foundation.FileManager

/// User-selectable display mode for the macOS menu bar status item.
enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case iconAndPercent = "icon_percent"
    case iconOnly = "icon_only"
    case percentOnly = "percent_only"
    case iconAndRemainingTime = "icon_time"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .iconAndPercent: return "圖示 ＋ 百分比"
        case .iconOnly: return "僅電池圖示"
        case .percentOnly: return "僅百分比"
        case .iconAndRemainingTime: return "圖示 ＋ 剩餘時間"
        }
    }
}

/// Visual skin theme for the desktop battery buddy.
enum BuddySkin: String, CaseIterable, Identifiable {
    case classic = "classic"
    case pixelMonster = "pixel"
    case cyberCore = "cyber"
    case arcReactor = "arc_reactor"
    case captainShield = "captain_shield"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .classic: return "經典靈動光球 🔮"
        case .pixelMonster: return "復古像素電池怪 👾"
        case .cyberCore: return "賽博微型反應堆 ⚛️"
        case .arcReactor: return "鋼鐵人方舟反應爐 🦾"
        case .captainShield: return "美國隊長汎合金之盾 🛡️"
        }
    }
}

/// A persistent daily record of battery health, capacity retention, and cycle count.
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
final class VoicePromptManager {
    static let shared = VoicePromptManager()
    private let synth = AVSpeechSynthesizer()

    func speak(text: String, isJarvis: Bool = false) {
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        if isJarvis {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-GB") ?? AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = 0.48
            utterance.pitchMultiplier = 0.95
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "zh-TW") ?? AVSpeechSynthesisVoice(language: "zh-CN")
            utterance.rate = 0.50
        }
        synth.speak(utterance)
    }
}

/// Rogue App & Energy Vampire Detective.
enum EnergyVampireDetective {
    private static let lock = NSLock()
    private static var isScanning = false

    static func scanTopEnergyVampires() -> [EnergyVampireApp] {
        lock.lock()
        guard !isScanning else {
            lock.unlock()
            return []
        }
        isScanning = true
        lock.unlock()

        defer {
            lock.lock()
            isScanning = false
            lock.unlock()
        }

        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = ["-Ao", "pid,%cpu,comm", "-r"]
        let pipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = pipe
        task.standardError = errPipe

        defer {
            try? pipe.fileHandleForReading.close()
            try? pipe.fileHandleForWriting.close()
            try? errPipe.fileHandleForReading.close()
            try? errPipe.fileHandleForWriting.close()
        }

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            guard let output = String(data: data, encoding: .utf8) else { return [] }
            let lines = output.components(separatedBy: .newlines).dropFirst()
            var apps: [EnergyVampireApp] = []
            let ignoredNames = ["WindowServer", "launchd", "kernel_task", "BatteryLogger", "ps", "loginwindow", "logd"]

            for line in lines {
                let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", omittingEmptySubsequences: true)
                guard parts.count >= 3,
                      let pid = Int(parts[0]),
                      let cpu = Double(parts[1]) else { continue }
                if cpu < 5.0 { break }

                let rawPath = parts[2...].joined(separator: " ")
                let url = URL(fileURLWithPath: rawPath)
                let name = url.deletingPathExtension().lastPathComponent
                if ignoredNames.contains(where: { name.localizedCaseInsensitiveContains($0) }) {
                    continue
                }

                let friendlyName: String
                let bundleId: String?
                if let runningApp = NSRunningApplication(processIdentifier: pid_t(pid)) {
                    friendlyName = runningApp.localizedName ?? name
                    bundleId = runningApp.bundleIdentifier
                } else {
                    friendlyName = name
                    bundleId = nil
                }

                apps.append(EnergyVampireApp(id: pid, name: friendlyName, cpuPercent: cpu, bundleId: bundleId))
                if apps.count >= 3 { break }
            }
            return apps
        } catch {
            return []
        }
    }
}

/// Smart Calendar Outing Predictor.
@MainActor
final class CalendarOutingPredictor {
    static let shared = CalendarOutingPredictor()
    private let eventStore = EKEventStore()

    func checkUpcomingOuting() async -> CalendarOutingAlert? {
        var isAuthorized = false
        if #available(macOS 14.0, *) {
            isAuthorized = (try? await eventStore.requestFullAccessToEvents()) ?? false
        } else {
            isAuthorized = (try? await eventStore.requestAccess(to: .event)) ?? false
        }
        guard isAuthorized else { return nil }

        let now = Date()
        let fourHoursLater = now.addingTimeInterval(4 * 3600)
        let predicate = eventStore.predicateForEvents(withStart: now, end: fourHoursLater, calendars: nil)
        let events = eventStore.events(matching: predicate)

        let outingKeywords = ["會議", "開會", "外勤", "出差", "拜訪", "航班", "高鐵", "飛機", "客戶", "聚餐", "出發", "meeting", "flight", "lunch", "dinner", "interview", "presentation", "train", "trip"]

        for event in events {
            guard !event.isAllDay else { continue }
            let text = "\(event.title ?? "") \(event.location ?? "")".lowercased()
            if outingKeywords.contains(where: { text.contains($0.lowercased()) }) {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                let timeStr = formatter.string(from: event.startDate)
                return CalendarOutingAlert(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "外出行程",
                    startTime: event.startDate,
                    timeDescription: "\(timeStr) 開始"
                )
            }
        }
        return nil
    }
}

// MARK: - GitHub Auto Update Checker
struct GitHubReleaseInfo: Decodable {
    let tagName: String
    let htmlUrl: String
    let name: String?
    let body: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case name
        case body
    }
}

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published var latestVersion: String? = nil
    @Published var releaseURL: URL? = nil
    @Published var hasUpdate: Bool = false
    @Published var isChecking: Bool = false
    @Published var statusMessage: String? = nil

    let currentVersion = "v2.0.0"

    func checkForUpdates(silent: Bool = true) {
        guard !isChecking else { return }
        isChecking = true
        if !silent { statusMessage = "正在連線 GitHub 檢查更新…" }

        guard let url = URL(string: "https://api.github.com/repos/mic1491/Battery-Logger-macOS/releases/latest") else {
            isChecking = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 8.0

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            Task { @MainActor in
                guard let self = self else { return }
                self.isChecking = false
                guard let data = data, error == nil,
                      let release = try? JSONDecoder().decode(GitHubReleaseInfo.self, from: data) else {
                    if !silent { self.statusMessage = "暫時無法取得 GitHub 更新資訊" }
                    return
                }

                let remoteTag = release.tagName.trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanRemote = remoteTag.replacingOccurrences(of: "v", with: "")
                let cleanCurrent = self.currentVersion.replacingOccurrences(of: "v", with: "")

                if cleanRemote.compare(cleanCurrent, options: .numeric) == .orderedDescending {
                    self.latestVersion = remoteTag
                    self.releaseURL = URL(string: release.htmlUrl)
                    self.hasUpdate = true
                    if !silent { self.statusMessage = "發現新版本 \(remoteTag)！" }
                } else {
                    self.hasUpdate = false
                    if !silent { self.statusMessage = "已是最新版本 (\(self.currentVersion))" }
                }
            }
        }.resume()
    }
}

/// Google Gemini AI integration service for battery diagnosis and interactive assistant.
@MainActor
final class GeminiService: ObservableObject {
    static let shared = GeminiService()

    @Published var isQuerying = false
    @Published var lastResponse: String?
    @Published var errorMessage: String?

    var apiKey: String {
        get { UserDefaults.standard.string(forKey: "geminiApiKey") ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "geminiApiKey") }
    }

    var selectedModel: String {
        get { UserDefaults.standard.string(forKey: "geminiSelectedModel") ?? "gemini-1.5-flash" }
        set { UserDefaults.standard.set(newValue, forKey: "geminiSelectedModel") }
    }

    var autoSpeakResponse: Bool {
        get { UserDefaults.standard.object(forKey: "geminiAutoSpeak") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "geminiAutoSpeak") }
    }

    func generateResponse(
        prompt: String,
        snapshot: BatterySnapshot,
        skin: BuddySkin,
        topVampires: [EnergyVampireApp],
        limit: Int?
    ) async -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            return "長官，尚未設定 Gemini API Key。請點擊「偏好設定」>「Google Gemini AI」輸入您的 API Key 即可啟動大腦！"
        }

        isQuerying = true
        errorMessage = nil

        let isIronMan = skin == .arcReactor
        let systemPrompt = """
        You are an advanced AI battery engineer and personal companion inside a Mac system.
        Persona: \(isIronMan ? "You are J.A.R.V.I.S., Tony Stark's sophisticated AI butler. Respond in witty, concise, highly professional British butler style. You may speak in Traditional Chinese or English when appropriate." : "You are a friendly, scientifically knowledgeable Mac battery guardian and energy advisor. Speak in warm, polite Traditional Chinese.")

        Current Real-time Mac Hardware Telemetry:
        • Device: \(snapshot.model) (\(snapshot.processor), \(snapshot.memory))
        • macOS: \(snapshot.macOS)
        • Battery Level: \(snapshot.percent.map { "\($0)%" } ?? "Unknown")
        • Power State: \(snapshot.externalPower == true ? "Connected to AC Charger" : "Discharging on Battery")
        • Charging Status: \(snapshot.powerStatusText)
        • Voltage: \(snapshot.voltage.map { "\(Double($0)/1000.0)V" } ?? "Unknown")
        • Wattage: \(snapshot.charging == true ? (snapshot.chargeWatts.map { "+\(String(format: "%.1f", $0))W" } ?? "0W") : (snapshot.dischargeWatts.map { "-\(String(format: "%.1f", $0))W" } ?? "0W"))
        • Temperature: \(snapshot.temperature.map { String(format: "%.1f°C", $0) } ?? "Unknown")
        • Battery Health (SOH): \(snapshot.healthPercent.map { String(format: "%.1f%%", $0) } ?? "Unknown")
        • Cycles: \(snapshot.cycles.map { "\($0) cycles" } ?? "Unknown")
        • Cell Imbalance: \(snapshot.cellBalanceText)
        • Hardware Charge Limit: \(limit.map { "\($0)%" } ?? "100%")
        • Active Top Energy Apps: \(topVampires.map { "\($0.name) (\(String(format: "%.0f", $0.cpuPercent))% CPU)" }.joined(separator: ", "))

        Instructions:
        1. Keep responses concise (under 120 words unless requested detailed report), direct, and actionable.
        2. Incorporate real battery electrochemistry (e.g. 30%-80% shallow charge cycles, avoidance of 4.3V high voltage stress, thermal safeguards).
        3. Maintain persona perfectly!
        """

        let model = selectedModel.isEmpty ? "gemini-1.5-flash" : selectedModel
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(key)") else {
            isQuerying = false
            return "API 網址格式錯誤。"
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": "\(systemPrompt)\n\nUser Question / Command: \(prompt)"]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 600
            ]
        ]

        guard let httpData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            isQuerying = false
            return "無法序列化請求資料。"
        }
        request.httpBody = httpData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            isQuerying = false

            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode != 200 {
                let errText = String(data: data, encoding: .utf8) ?? "未知錯誤"
                return "Gemini API 呼叫失敗 (\(httpResp.statusCode))：\(errText.prefix(100))"
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let firstCandidate = candidates.first,
                  let content = firstCandidate["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let firstPart = parts.first,
                  let text = firstPart["text"] as? String else {
                return "無法解析 Gemini 回應內容。"
            }

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            self.lastResponse = trimmed

            if autoSpeakResponse {
                VoicePromptManager.shared.speak(text: trimmed, isJarvis: isIronMan)
            }

            return trimmed
        } catch {
            isQuerying = false
            self.errorMessage = error.localizedDescription
            return "連線失敗：\(error.localizedDescription)"
        }
    }
}

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

private struct LogSummary {
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

private struct BatteryCompatibility: Sendable {
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

enum IPhoneNotifyThreshold: String, CaseIterable, Identifiable {
    case atLimit = "atLimit"
    case at100 = "at100"
    case both = "both"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .atLimit:
            return "達到設定的充電上限時通知（例如 80% / 85% / 90%）"
        case .at100:
            return "達到 100% 完全充飽時通知"
        case .both:
            return "充電上限與 100% 充飽時皆通知"
        }
    }
}

@MainActor
final class BatteryModel: ObservableObject {
    @Published var snapshot = BatterySnapshot()
    @Published var recording = false
    @Published var logPath = "尚未開始記錄"
    @Published var processInfo = "程序耗電需用「活動監視器」查看；詳情見下方說明。"
    @Published var errorMessage: String?
    @Published var compareResult: String?
    @Published var comparisonFileA = ""
    @Published var comparisonFileB = ""
    @Published var launchAtLoginEnabled = false
    @Published var launchAtLoginNeedsApproval = false
    @Published var launchAtLoginMessage: String?
    @Published var chargeLimit: Int? = 100
    @Published var userTargetLimit: Int = 85
    @Published var isSettingLimit = false
    @Published var limitMessage: String?
    @Published var smartAutoPilot = true
    @Published var boostModeActive = false
    @Published var thermalThrottleActive = false
    @Published var smartStatusTip: String?
    @Published var isAppleSilicon: Bool = false

    var displayChargeLimit: Int {
        return userTargetLimit
    }

    var displayChargeLimitBadge: String? {
        if isSailingPaused {
            return "⛵️ 航行中"
        } else if isDischargeOnACActive {
            return "🔻 放電中"
        } else if userTargetLimit < 100 {
            return "🛡️ 旁路保護"
        } else {
            return nil
        }
    }

    @Published var menuBarDisplayMode: MenuBarDisplayMode {
        didSet {
            UserDefaults.standard.set(menuBarDisplayMode.rawValue, forKey: "menuBarDisplayMode")
        }
    }
    @Published var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }
    @Published var notifyOnLimitReached: Bool {
        didSet { UserDefaults.standard.set(notifyOnLimitReached, forKey: "notifyOnLimitReached") }
    }
    @Published var notifyOnHighTemp: Bool {
        didSet { UserDefaults.standard.set(notifyOnHighTemp, forKey: "notifyOnHighTemp") }
    }
    @Published var notifyOnLowBattery: Bool {
        didSet { UserDefaults.standard.set(notifyOnLowBattery, forKey: "notifyOnLowBattery") }
    }
    @Published var buddyLocked: Bool {
        didSet { UserDefaults.standard.set(buddyLocked, forKey: "buddyLocked") }
    }
    @Published var autoShowBuddyOnLaunch: Bool {
        didSet { UserDefaults.standard.set(autoShowBuddyOnLaunch, forKey: "autoShowBuddyOnLaunch") }
    }
    @Published var buddySkin: BuddySkin {
        didSet { UserDefaults.standard.set(buddySkin.rawValue, forKey: "buddySkin") }
    }
    @Published var edgeDockingEnabled: Bool {
        didSet { UserDefaults.standard.set(edgeDockingEnabled, forKey: "buddyEdgeDocking") }
    }
    @Published var notifyIPhoneViaIMessage: Bool {
        didSet { UserDefaults.standard.set(notifyIPhoneViaIMessage, forKey: "notifyIPhoneViaIMessage") }
    }
    @Published var iPhoneIMessageTarget: String {
        didSet { UserDefaults.standard.set(iPhoneIMessageTarget, forKey: "iPhoneIMessageTarget") }
    }
    @Published var iPhoneNotifyThreshold: IPhoneNotifyThreshold {
        didSet { UserDefaults.standard.set(iPhoneNotifyThreshold.rawValue, forKey: "iPhoneNotifyThreshold") }
    }
    @Published var isTestingIMessage = false
    @Published var iMessageTestResult: (isSuccess: Bool, message: String)?

    // 🧠 6 Intelligent Subsystems State
    @Published var voicePromptEnabled: Bool {
        didSet { UserDefaults.standard.set(voicePromptEnabled, forKey: "voicePromptEnabled") }
    }
    @Published var rogueVampireDetectionEnabled: Bool {
        didSet { UserDefaults.standard.set(rogueVampireDetectionEnabled, forKey: "rogueVampireDetectionEnabled") }
    }
    @Published var calendarOutingPredictionEnabled: Bool {
        didSet { UserDefaults.standard.set(calendarOutingPredictionEnabled, forKey: "calendarOutingPredictionEnabled") }
    }
    @Published var topEnergyVampires: [EnergyVampireApp] = []
    @Published var isRogueDrainAlert = false
    @Published var rogueDrainWatts: Double = 0.0
    @Published var calendarOutingAlert: CalendarOutingAlert?
    @Published var lastSleepReport: SleepGuardianReport?
    @Published var isSystemSleeping = false

    // 🧠 Gemini AI Assistant State
    @Published var geminiAiQuery: String = ""
    @Published var geminiAiResponse: String?
    @Published var isGeminiQuerying = false
    @Published var geminiChatHistory: [(isUser: Bool, text: String)] = []

    // 🌊 1. Sailing Mode & Discharge on AC & Calibration
    @Published var sailingModeEnabled: Bool {
        didSet { UserDefaults.standard.set(sailingModeEnabled, forKey: "sailingModeEnabled") }
    }
    @Published var sailingBuffer: Int {
        didSet { UserDefaults.standard.set(sailingBuffer, forKey: "sailingBuffer") }
    }
    @Published var isSailingPaused = false
    @Published var isDischargeOnACActive = false
    @Published var lastCalibrationDate: Date?
    @Published var isCalibrating = false
    @Published var calibrationStep: Int = 0

    // 🚀 2. Scheduled Departure & Smart Plug Webhook
    @Published var departureScheduleEnabled: Bool {
        didSet { UserDefaults.standard.set(departureScheduleEnabled, forKey: "departureScheduleEnabled") }
    }
    @Published var departureTimeString: String {
        didSet { UserDefaults.standard.set(departureTimeString, forKey: "departureTimeString") }
    }
    @Published var smartPlugWebhookEnabled: Bool {
        didSet { UserDefaults.standard.set(smartPlugWebhookEnabled, forKey: "smartPlugWebhookEnabled") }
    }
    @Published var smartPlugTurnOffUrl: String {
        didSet { UserDefaults.standard.set(smartPlugTurnOffUrl, forKey: "smartPlugTurnOffUrl") }
    }
    @Published var smartPlugTurnOnUrl: String {
        didSet { UserDefaults.standard.set(smartPlugTurnOnUrl, forKey: "smartPlugTurnOnUrl") }
    }

    // 🖥️ 3. Dock Mode (External Display)
    @Published var dockModeEnabled: Bool {
        didSet { UserDefaults.standard.set(dockModeEnabled, forKey: "dockModeEnabled") }
    }
    @Published var isDockModeEngaged = false

    // 🛡️ 4. Root LaunchDaemon & Privileged SUID Helper
    @Published var isLaunchDaemonInstalled = false
    @Published var isPrivilegedHelperInstalled = false
    @Published var cellSwellWarningActive = false

    // 🍃 5. Auto Low Power Mode
    @Published var autoLowPowerModeEnabled: Bool {
        didSet { UserDefaults.standard.set(autoLowPowerModeEnabled, forKey: "autoLowPowerModeEnabled") }
    }
    @Published var isLowPowerModeActive = false

    @Published var sessionStartTime = Date()
    @Published var healthHistory: [BatteryDailyHealthRecord] = []

    private var timer: Timer?
    private var refreshTimer: Timer?
    private var iopsRunLoopSource: CFRunLoopSource?
    private var systemDetails: SystemDetails?
    private var logHandle: FileHandle?
    private var previous: (time: Date, watts: Double, onBattery: Bool)?
    private var cumulativeWh = 0.0
    private let sampleInterval: TimeInterval = 10
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var lastNotifiedPct: Int?
    private var lastObservedOnAC: Bool?
    private var lastThermalThrottleTime: Date?
    private var notifiedIPhoneThresholds: Set<Int> = []
    private var sleepStartTime: Date?
    private var sleepStartPct: Int?
    private var sleepStartTemp: Double?
    private var lastVoiceTriggeredLevel: Int?
    private var lastVampireScanTime: Date?

    private var healthHistoryFileURL: URL? {
        guard let folder = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("BatteryLogger", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("health_history.json")
    }

    init() {
        let savedMode = UserDefaults.standard.string(forKey: "menuBarDisplayMode") ?? MenuBarDisplayMode.iconAndPercent.rawValue
        self.menuBarDisplayMode = MenuBarDisplayMode(rawValue: savedMode) ?? .iconAndPercent
        self.notificationsEnabled = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
        self.notifyOnLimitReached = UserDefaults.standard.object(forKey: "notifyOnLimitReached") as? Bool ?? true
        self.notifyOnHighTemp = UserDefaults.standard.object(forKey: "notifyOnHighTemp") as? Bool ?? true
        self.notifyOnLowBattery = UserDefaults.standard.object(forKey: "notifyOnLowBattery") as? Bool ?? true
        self.buddyLocked = UserDefaults.standard.bool(forKey: "buddyLocked")
        self.autoShowBuddyOnLaunch = UserDefaults.standard.object(forKey: "autoShowBuddyOnLaunch") as? Bool ?? false
        let savedSkin = UserDefaults.standard.string(forKey: "buddySkin") ?? BuddySkin.classic.rawValue
        self.buddySkin = BuddySkin(rawValue: savedSkin) ?? .classic
        self.edgeDockingEnabled = UserDefaults.standard.object(forKey: "buddyEdgeDocking") as? Bool ?? true

        self.notifyIPhoneViaIMessage = UserDefaults.standard.bool(forKey: "notifyIPhoneViaIMessage")
        self.iPhoneIMessageTarget = UserDefaults.standard.string(forKey: "iPhoneIMessageTarget") ?? ""
        let savedThreshold = UserDefaults.standard.string(forKey: "iPhoneNotifyThreshold") ?? IPhoneNotifyThreshold.atLimit.rawValue
        self.iPhoneNotifyThreshold = IPhoneNotifyThreshold(rawValue: savedThreshold) ?? .atLimit

        self.voicePromptEnabled = UserDefaults.standard.object(forKey: "voicePromptEnabled") as? Bool ?? true
        self.rogueVampireDetectionEnabled = UserDefaults.standard.object(forKey: "rogueVampireDetectionEnabled") as? Bool ?? true
        self.calendarOutingPredictionEnabled = UserDefaults.standard.object(forKey: "calendarOutingPredictionEnabled") as? Bool ?? true

        self.sailingModeEnabled = UserDefaults.standard.bool(forKey: "sailingModeEnabled")
        let savedBuf = UserDefaults.standard.integer(forKey: "sailingBuffer")
        self.sailingBuffer = savedBuf == 0 ? 5 : savedBuf
        let calibTs = UserDefaults.standard.double(forKey: "lastCalibrationDateTs")
        self.lastCalibrationDate = calibTs > 0 ? Date(timeIntervalSince1970: calibTs) : nil

        self.departureScheduleEnabled = UserDefaults.standard.bool(forKey: "departureScheduleEnabled")
        self.departureTimeString = UserDefaults.standard.string(forKey: "departureTimeString") ?? "08:30"
        self.smartPlugWebhookEnabled = UserDefaults.standard.bool(forKey: "smartPlugWebhookEnabled")
        self.smartPlugTurnOffUrl = UserDefaults.standard.string(forKey: "smartPlugTurnOffUrl") ?? ""
        self.smartPlugTurnOnUrl = UserDefaults.standard.string(forKey: "smartPlugTurnOnUrl") ?? ""

        self.dockModeEnabled = UserDefaults.standard.object(forKey: "dockModeEnabled") as? Bool ?? true
        self.isLaunchDaemonInstalled = FileManager.default.fileExists(atPath: "/Library/LaunchDaemons/local.codex.batterylogger.helper.plist")
        self.isPrivilegedHelperInstalled = FileManager.default.fileExists(atPath: "/usr/local/bin/smc-battery-tool")
        self.autoLowPowerModeEnabled = UserDefaults.standard.object(forKey: "autoLowPowerModeEnabled") as? Bool ?? true

        #if arch(arm64)
        self.isAppleSilicon = true
        #else
        var isArm64 = false
        var size = MemoryLayout<Int>.size
        var val: Int = 0
        if sysctlbyname("hw.optional.arm64", &val, &size, nil, 0) == 0 && val == 1 {
            isArm64 = true
        }
        self.isAppleSilicon = isArm64
        #endif

        let savedTarget = UserDefaults.standard.integer(forKey: "userTargetLimit")
        self.userTargetLimit = (savedTarget >= 70 && savedTarget <= 100) ? savedTarget : 85

        loadHealthHistory()
        syncLaunchAtLoginStatus()
        refresh()
        if (self.snapshot.chargeLimit ?? 100) < 70 {
            self.setChargeLimit(self.userTargetLimit)
        }
        checkCalendarOutings()

        let center = NSWorkspace.shared.notificationCenter
        sleepObserver = center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.recordPowerEvent("sleep")
                self?.handleSleepStart()
            }
        }
        wakeObserver = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.recordPowerEvent("wake")
                self?.handleSleepWake()
                self?.refresh()
                self?.reassertChargeLimitOnWake()
                self?.checkCalendarOutings()
            }
        }
        // Fallback coalesced safety timer: hardware changes trigger instantly via IOPSNotificationCreateRunLoopSource below
        let fallbackTimer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        fallbackTimer.tolerance = 5.0
        RunLoop.main.add(fallbackTimer, forMode: .common)
        refreshTimer = fallbackTimer

        // Hardware IOKit power source notification: instant refresh on any charge/level change
        let loopSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let model = Unmanaged<BatteryModel>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                model.refresh()
            }
        }, Unmanaged.passUnretained(self).toOpaque())
        if let loopSource = loopSource?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), loopSource, .commonModes)
            self.iopsRunLoopSource = loopSource
        }

        // System appearance theme change observer: instant redraw when user switches Light/Dark mode
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.objectWillChange.send()
        }

        if autoShowBuddyOnLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                BatteryLoggerAppDelegate.toggleBuddyWindow(model: self)
            }
        }
    }

    func reassertChargeLimitOnWake() {
        guard userTargetLimit < 100 else { return }
        setChargeLimit(userTargetLimit)
    }

    private func loadHealthHistory() {
        guard let url = healthHistoryFileURL,
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([BatteryDailyHealthRecord].self, from: data) else {
            return
        }
        self.healthHistory = list
    }

    private func recordDailyHealthSample(snapshot: BatterySnapshot) {
        guard let health = snapshot.healthPercent, let full = snapshot.fullCapacity, let design = snapshot.designCapacity, let cycles = snapshot.cycles else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayStr = formatter.string(from: Date())

        var list = healthHistory
        if let idx = list.firstIndex(where: { $0.date == todayStr }) {
            list[idx] = BatteryDailyHealthRecord(
                date: todayStr,
                percent: snapshot.percent ?? 0,
                health: health,
                fullCapacity: full,
                designCapacity: design,
                cycles: cycles,
                maxMvDiff: snapshot.cellImbalanceMv,
                temperature: snapshot.temperature
            )
        } else {
            list.append(BatteryDailyHealthRecord(
                date: todayStr,
                percent: snapshot.percent ?? 0,
                health: health,
                fullCapacity: full,
                designCapacity: design,
                cycles: cycles,
                maxMvDiff: snapshot.cellImbalanceMv,
                temperature: snapshot.temperature
            ))
        }

        if list.count > 365 {
            list = Array(list.suffix(365))
        }
        self.healthHistory = list
        if let url = healthHistoryFileURL, let data = try? JSONEncoder().encode(list) {
            try? data.write(to: url)
        }
    }

    func exportDiagnosticReport() {
        let snap = snapshot
        let dateStr = ISO8601DateFormatter().string(from: Date())
        let report = """
        ================================================================================
        Mac 電池健康度與硬體深度診斷報告 (Battery Diagnostic Report)
        產生時間：\(dateStr)
        開發者：Matt · Battery Logger v2.0.0
        ================================================================================

        【一、 系統與硬體資訊】
        • 設備型號：\(snap.model)
        • 處理器架構：\(snap.processor)
        • 記憶體容量：\(snap.memory)
        • 作業系統：macOS \(snap.macOS) (Build \(snap.build))
        • 電池序號：\(snap.serialNumber)
        • 電池製造商：\(snap.manufacturer)
        • 電池控制器晶片：\(snap.controllerModel)

        【二、 電池健康與壽命指標】
        • 當前電量百分比：\(snap.percent.map { "\($0)%" } ?? "—")
        • 電池健康狀態：\(snap.condition)
        • 電池健康度 (SoH)：\(snap.healthPercent.map { String(format: "%.1f%%", $0) } ?? "—")
        • 當前滿充電容量：\(snap.fullCapacity.map { "\($0) mAh" } ?? "—")
        • 原廠出廠設計容量：\(snap.designCapacity.map { "\($0) mAh" } ?? "—")
        • 已完成循環次數：\(snap.cycles.map { "\($0) 次" } ?? "—")
        • 壽命週期階段：\(snap.cycleStageExplanation)
        • 更換維修建議：\(snap.replacementAdvice)

        【三、 電芯微觀均衡評估 (Cell Balance)】
        • 各電芯即時電壓：\(snap.cellVoltages.isEmpty ? "系統未公開" : snap.cellVoltages.map { "\($0) mV" }.joined(separator: " · "))
        • 電芯最大壓差：\(snap.cellImbalanceMv.map { "\($0) mV" } ?? "—")
        • 壓差健康評估：\(snap.cellBalanceText)

        【四、 電源與即時熱力狀態】
        • 外接電源狀態：\(snap.externalPower == true ? "已連接電源轉接器" : "電池放電運作中")
        • 充電狀態：\(snap.powerStatusText)
        • 即時工作電壓：\(snap.voltage.map { String(format: "%.3f V", Double($0) / 1000.0) } ?? "—")
        • 即時充放電流：\(snap.current.map { "\($0) mA" } ?? "—")
        • 即時運作功率：\(snap.charging == true ? (snap.chargeWatts.map { String(format: "+%.2f W (充電中)", $0) } ?? "—") : (snap.dischargeWatts.map { String(format: "-%.2f W (放電中)", $0) } ?? "—"))
        • 電池即時溫度：\(snap.temperature.map { String(format: "%.1f °C", $0) } ?? "—")
        • 當前充電上限設定：\(displayChargeLimit)% (\(displayChargeLimitBadge ?? "常駐保護"))

        【五、 智慧保養綜合分析】
        • 狀態標籤：\(snap.impactAnalysis.level.tagText)
        • 診斷概述：\(snap.impactAnalysis.title)
        • 化學原理解析：\(snap.impactAnalysis.description)
        • 原廠保養建議：\(snap.impactAnalysis.suggestion)
        ================================================================================
        """

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Mac_Battery_Diagnostic_Report_\(ISO8601DateFormatter().string(from: Date()).prefix(10)).txt"
        panel.title = "儲存電池健康診斷報告"
        panel.message = "選取儲存位置以保存電池完整硬體診斷報告。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? report.write(to: url, atomically: true, encoding: String.Encoding.utf8)
    }

    deinit {
        refreshTimer?.invalidate()
        if let iopsRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), iopsRunLoopSource, .commonModes)
        }
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }

    func refresh() {
        guard !isSystemSleeping else { return }
        let needsSystemDetails = systemDetails == nil
        Task.detached(priority: .utility) {
            let details = needsSystemDetails ? Self.readSystemDetails() : nil
            let result = Self.readBatterySnapshot()
            await MainActor.run {
                if let details { self.systemDetails = details }
                var updated = result
                if let details = self.systemDetails {
                    updated.model = details.model
                    updated.processor = details.processor
                    updated.memory = details.memory
                    updated.macOS = details.macOS
                    updated.build = details.build
                    updated.condition = details.condition
                }
                let changed = self.snapshot.percent != updated.percent ||
                              self.snapshot.charging != updated.charging ||
                              self.snapshot.externalPower != updated.externalPower
                self.snapshot = updated
                self.chargeLimit = updated.chargeLimit
                self.applySmartGovernor(snapshot: updated)
                self.checkLimitNotifications(snapshot: updated)
                self.checkIPhoneNotifications(snapshot: updated)
                self.recordDailyHealthSample(snapshot: updated)
                self.checkEnergyVampires(snapshot: updated)
                self.triggerVoicePrompts(snapshot: updated)
                BatteryNotificationManager.shared.checkAndNotify(
                    snapshot: updated,
                    limit: self.displayChargeLimit,
                    enabled: self.notificationsEnabled,
                    onLimit: self.notifyOnLimitReached,
                    onTemp: self.notifyOnHighTemp,
                    onLow: self.notifyOnLowBattery
                )
                if changed {
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
        }
    }

    private func applySmartGovernor(snapshot: BatterySnapshot) {
        guard smartAutoPilot else { return }
        let isAC = snapshot.externalPower == true
        let temp = snapshot.temperature ?? 25.0
        let currentLimit = userTargetLimit

        // 1. Unplug detection: If user enabled Boost Mode (100%) and unplugged, auto-reset to 85% for next plug-in
        if let lastAC = lastObservedOnAC {
            if lastAC == true && isAC == false {
                // User just unplugged charger!
                if boostModeActive {
                    boostModeActive = false
                    smartStatusTip = "偵測到已拔除充電器出門，下次連接將自動恢復 85% 最佳保養。"
                    Self.postNotification(
                        title: "已退出外出衝刺模式",
                        body: "偵測到電源線已拔除，下次充電將自動回到 85% 保養上限。"
                    )
                    // Set SMC limit back to 85 in background
                    setChargeLimit(85)
                }
            }
        }
        lastObservedOnAC = isAC

        // 2. Thermal Safeguard: If battery temperature >= 36.0°C and charging limit is 100% or 90%
        if isAC && temp >= 36.5 && currentLimit > 85 && !thermalThrottleActive {
            let now = Date()
            if lastThermalThrottleTime == nil || now.timeIntervalSince(lastThermalThrottleTime!) > 600 {
                lastThermalThrottleTime = now
                thermalThrottleActive = true
                smartStatusTip = String(format: "高溫熱防護啟動（%.1f°C），已自動下調充電上限至 85%% 防止電解液產氣膨脹。", temp)
                Self.postNotification(
                    title: "🌡️ 高溫熱防護啟動",
                    body: String(format: "電池溫度達 %.1f°C，智慧管家已主動下調至 85%% 以保護電芯。", temp)
                )
                setChargeLimit(85)
            }
        } else if temp < 33.0 && thermalThrottleActive {
            thermalThrottleActive = false
            smartStatusTip = nil
        }

        // 3. Sailing Mode (航行保護死區：達上限暫停，跌破緩衝再補電，消滅 79%~80% 微循環)
        if sailingModeEnabled && isAC && !boostModeActive && !isDischargeOnACActive {
            let target = userTargetLimit
            let lowerBound = max(60, target - sailingBuffer)
            if let pct = snapshot.percent {
                if pct >= target && !isSailingPaused {
                    isSailingPaused = true
                    smartStatusTip = "航行保護中：已達 \(target)% 上限，允許自然滑行至 \(lowerBound)% 以免微循環磨損。"
                    writeSMCHardwareLimit(lowerBound)
                    triggerSmartPlug(turnOff: true)
                } else if pct <= lowerBound && isSailingPaused {
                    isSailingPaused = false
                    smartStatusTip = "航行結束：電量已降至 \(lowerBound)%，恢復 \(target)% 溫和充電。"
                    writeSMCHardwareLimit(target)
                    triggerSmartPlug(turnOff: false)
                }
            }
        } else if !sailingModeEnabled && isSailingPaused {
            isSailingPaused = false
            writeSMCHardwareLimit(userTargetLimit)
        }

        // 4. Discharge on AC (插電主動放電降壓)
        if isDischargeOnACActive && isAC {
            let target = userTargetLimit
            if let pct = snapshot.percent {
                if pct <= target {
                    isDischargeOnACActive = false
                    smartStatusTip = "主動放電完成：電量已降至 \(target)% 上限，切回外接電源旁路保護！"
                    writeSMCHardwareLimit(target)
                    Self.postNotification(title: "主動放電完成", body: "電量已降至 \(target)%，系統恢復外接電源旁路。")
                }
            }
        }

        // 5. Dock Mode (外接顯示器底座模式：自動鎖定 75% 甜蜜點)
        if dockModeEnabled && isAC && !boostModeActive && !isDischargeOnACActive && !isSailingPaused {
            let isMultiScreen = NSScreen.screens.count > 1
            if isMultiScreen && !isDockModeEngaged && userTargetLimit > 75 {
                isDockModeEngaged = true
                smartStatusTip = "桌面底座模式：偵測到外接顯示器，自動以 75% 甜蜜點供電防範高溫。"
                writeSMCHardwareLimit(75)
            } else if !isMultiScreen && isDockModeEngaged {
                isDockModeEngaged = false
                smartStatusTip = "已拔除外接顯示器，恢復 \(userTargetLimit)% 最佳保養。"
                writeSMCHardwareLimit(userTargetLimit)
            }
        }

        // 6. Scheduled Departure (特斯拉級出門前定時滿電衝刺)
        if departureScheduleEnabled && isAC && !boostModeActive {
            let comps = departureTimeString.split(separator: ":").compactMap { Int($0) }
            if comps.count == 2 {
                let depH = comps[0]
                let depM = comps[1]
                let nowComps = Calendar.current.dateComponents([.hour, .minute], from: Date())
                if let nowH = nowComps.hour, let nowM = nowComps.minute {
                    let nowTotal = nowH * 60 + nowM
                    let depTotal = depH * 60 + depM
                    let diff = depTotal - nowTotal
                    if diff >= 0 && diff <= 60 {
                        activateBoostMode()
                        let isIronMan = buddySkin == .arcReactor
                        let prompt = isIronMan ?
                            "Sir, departure scheduled in \(diff) minutes. Engaging full boost charge to 100 percent." :
                            "長官，距離預約出門還有 \(diff) 分鐘，已自動啟動 100% 滿電衝刺！"
                        VoicePromptManager.shared.speak(text: prompt, isJarvis: isIronMan)
                        Self.postNotification(title: "🚀 出門預約衝刺啟動", body: "預定出門時間即將到達，已切換至 100% 滿充模式。")
                    }
                }
            }
        }

        // 7. Cell Swell Imbalance Warning (電芯微膨脹與壓差警報)
        if let diff = snapshot.cellImbalanceMv, diff >= 55 && !cellSwellWarningActive {
            cellSwellWarningActive = true
            Self.postNotification(
                title: "⚠️ 電芯壓差過大警報（\(diff) mV）",
                body: "偵測到多電芯嚴重不均衡，可能為局部微膨脹或電極老化前兆，建議檢查觸控板底蓋平整度。"
            )
        } else if let diff = snapshot.cellImbalanceMv, diff < 40 {
            cellSwellWarningActive = false
        }

        // 8. Auto Low Power Mode (低電量自動啟用 macOS 低耗電模式)
        if autoLowPowerModeEnabled {
            if !isAC, let pct = snapshot.percent, pct <= 20 && !isLowPowerModeActive {
                isLowPowerModeActive = true
                setSystemLowPowerMode(enabled: true)
                smartStatusTip = "🍃 低耗電模式中：電量剩餘 \(pct)%，已自動限制 CPU/GPU 功耗以延長續航。"
                Self.postNotification(
                    title: "🍃 已自動啟用 macOS 低耗電模式",
                    body: "電量剩餘 \(pct)%，已主動降低背景能耗，為您多爭取約 1 小時外出續航。"
                )
            } else if isAC && isLowPowerModeActive {
                isLowPowerModeActive = false
                setSystemLowPowerMode(enabled: false)
                smartStatusTip = "⚡️ 已接上電源：自動退出低耗電模式，恢復全效能運算。"
                Self.postNotification(
                    title: "⚡️ 已退出低耗電模式",
                    body: "連接充電器，已自動恢復 Mac 最高峰值效能。"
                )
            }
        }

        // 9. Battery Health Degradation Milestone (SOH 掉階與保固診斷)
        checkBatteryHealthDegradation(snapshot: snapshot)
    }

    private func checkBatteryHealthDegradation(snapshot: BatterySnapshot) {
        guard let health = snapshot.healthPercent, health > 10 else { return }
        let lastSaved = UserDefaults.standard.double(forKey: "lastSavedHealthPercent")
        if lastSaved <= 0 {
            UserDefaults.standard.set(health, forKey: "lastSavedHealthPercent")
            return
        }

        if health < lastSaved {
            let diff = lastSaved - health
            if diff >= 0.8 {
                UserDefaults.standard.set(health, forKey: "lastSavedHealthPercent")
                if health < 80.0 {
                    Self.postNotification(
                        title: "🚨 電池最大容量跌破 80% 臨界值！",
                        body: "目前健康度為 \(String(format: "%.1f%%", health))。若仍在 AppleCare+ 或原廠 1 年保固期內，可至 Apple Store 直營店預約免費更換全新原廠電池！"
                    )
                } else {
                    Self.postNotification(
                        title: "📉 電池最大容量掉階提醒",
                        body: "電池最大容量由 \(String(format: "%.1f%%", lastSaved)) 變動為 \(String(format: "%.1f%%", health))。建議持續維持 85% 限制以延緩進一步氧化衰退。"
                    )
                }
            }
        }
    }

    func triggerSmartPlug(turnOff: Bool) {
        guard smartPlugWebhookEnabled else { return }
        let urlStr = turnOff ? smartPlugTurnOffUrl : smartPlugTurnOnUrl
        guard let url = URL(string: urlStr.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme?.hasPrefix("http") == true else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        URLSession.shared.dataTask(with: req) { _, _, _ in }.resume()
    }

    func toggleDischargeOnAC() {
        if isDischargeOnACActive {
            isDischargeOnACActive = false
            writeSMCHardwareLimit(userTargetLimit)
            limitMessage = "已取消主動放電模式"
        } else {
            guard snapshot.externalPower == true, let pct = snapshot.percent, pct > userTargetLimit else {
                limitMessage = "目前電量未高於上限或未連接電源"
                return
            }
            isDischargeOnACActive = true
            smartStatusTip = "主動放電中：正在將電量降至 \(userTargetLimit)%…"
            writeSMCHardwareLimit(userTargetLimit)
        }
    }

    func startCalibration() {
        isCalibrating = true
        calibrationStep = 1
        smartStatusTip = "【第 1 步】請拔掉充電線，正常使用至電量低於 15%（放電基準重置）。"
    }

    func advanceCalibrationStep() {
        if calibrationStep == 1 {
            calibrationStep = 2
            smartStatusTip = "【第 2 步】請連接充電器，開啟 100% 慢速充飽並持續插電 2 小時（校準電量計）。"
            activateBoostMode()
        } else if calibrationStep == 2 {
            calibrationStep = 0
            isCalibrating = false
            lastCalibrationDate = Date()
            UserDefaults.standard.set(lastCalibrationDate?.timeIntervalSince1970, forKey: "lastCalibrationDateTs")
            smartStatusTip = "🎉 庫侖計校準流程已順利完成！晶片基準點已重置。"
            setChargeLimit(userTargetLimit)
        }
    }

    func installLaunchDaemonHelper() {
        let targetVal = userTargetLimit
        let script = """
        do shell script "mkdir -p /Library/LaunchDaemons && cat << 'EOF' > /Library/LaunchDaemons/local.codex.batterylogger.helper.plist
        <?xml version=\\"1.0\\" encoding=\\"UTF-8\\"?>
        <!DOCTYPE plist PUBLIC \\"-//Apple//DTD PLIST 1.0//EN\\" \\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\\">
        <plist version=\\"1.0\\">
        <dict>
            <key>Label</key>
            <string>local.codex.batterylogger.helper</string>
            <key>ProgramArguments</key>
            <array>
                <string>/Applications/Battery Logger.app/Contents/Resources/smc-battery-tool</string>
                <string>write</string>
                <string>\(targetVal)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
        </dict>
        </plist>
        EOF
        launchctl load /Library/LaunchDaemons/local.codex.batterylogger.helper.plist 2>/dev/null || true" with administrator privileges
        """
        var err: NSDictionary?
        let res = NSAppleScript(source: script)?.executeAndReturnError(&err)
        if res != nil && err == nil {
            isLaunchDaemonInstalled = true
            Self.postNotification(title: "開機守護安裝成功", body: "系統即使重新開機停留在登入畫面，亦會自動維持 \(targetVal)% 充電上限！")
        } else {
            errorMessage = "安裝失敗：需管理員授權以寫入 /Library/LaunchDaemons"
        }
    }

    func uninstallLaunchDaemonHelper() {
        let script = """
        do shell script "launchctl unload /Library/LaunchDaemons/local.codex.batterylogger.helper.plist 2>/dev/null || true; rm -f /Library/LaunchDaemons/local.codex.batterylogger.helper.plist" with administrator privileges
        """
        var err: NSDictionary?
        let res = NSAppleScript(source: script)?.executeAndReturnError(&err)
        if res != nil && err == nil {
            isLaunchDaemonInstalled = false
            Self.postNotification(title: "開機守護已解除", body: "已成功移除底層開機守護服務。")
        }
    }

    func installPrivilegedHelper() {
        var toolPath: String?
        if let bundled = Bundle.main.url(forResource: "smc-battery-tool", withExtension: nil)?.path,
           FileManager.default.fileExists(atPath: bundled) {
            toolPath = bundled
        } else {
            let candidates = [
                "/Applications/Battery Logger.app/Contents/Resources/smc-battery-tool",
                URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/smc-battery-tool").path,
                "/tmp/smc_battery_tool_universal",
                "/tmp/smc_battery_tool"
            ]
            toolPath = candidates.first(where: { FileManager.default.fileExists(atPath: $0) })
        }

        guard let tool = toolPath else {
            errorMessage = "找不到內置 smc-battery-tool 檔案，無法安裝特權服務。"
            return
        }

        let script = """
        do shell script "mkdir -p /usr/local/bin && cp -f '\(tool)' /usr/local/bin/smc-battery-tool && chown root:wheel /usr/local/bin/smc-battery-tool && chmod 4755 /usr/local/bin/smc-battery-tool" with administrator privileges
        """
        var err: NSDictionary?
        let res = NSAppleScript(source: script)?.executeAndReturnError(&err)
        if res != nil && err == nil {
            isPrivilegedHelperInstalled = true
            Self.postNotification(title: "免密碼 Helper 安裝成功", body: "從此所有充電上限調節、航行滑行與底座模式切換皆全自動靜默執行，不再跳出密碼框！")
        } else {
            errorMessage = "安裝失敗：需管理員授權以複製並設定 SUID。"
        }
    }

    func uninstallPrivilegedHelper() {
        let script = "do shell script \"rm -f /usr/local/bin/smc-battery-tool\" with administrator privileges"
        var err: NSDictionary?
        let res = NSAppleScript(source: script)?.executeAndReturnError(&err)
        if res != nil && err == nil {
            isPrivilegedHelperInstalled = false
            Self.postNotification(title: "免密碼 Helper 已解除", body: "已成功從系統移除特權工具。")
        }
    }

    func setSystemLowPowerMode(enabled: Bool) {
        let arg = enabled ? "1" : "0"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        proc.arguments = ["-a", "lowpowermode", arg]
        try? proc.run()
    }

    func handleURL(_ url: URL) {
        guard url.scheme == "batterylogger" else { return }
        let host = url.host ?? url.path
        if host == "boost" {
            activateBoostMode()
        } else if host == "limit" {
            if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let valStr = comps.queryItems?.first(where: { $0.name == "value" })?.value,
               let val = Int(valStr), (50...100).contains(val) {
                setChargeLimit(val)
            }
        } else if host == "discharge" {
            toggleDischargeOnAC()
        } else if host == "sailing" {
            sailingModeEnabled.toggle()
        } else if host == "status" {
            BatteryLoggerAppDelegate.showMainWindow()
        }
    }

    func activateBoostMode() {
        boostModeActive = true
        smartStatusTip = "外出衝刺模式中：本次將充至 100%，出門拔掉充電線後會自動回歸 85% 保養。"
        setChargeLimit(100)
    }

    struct BatteryCareAdvice {
        let actionTitle: String
        let actionTip: String
        let cycleScience: String
        let badgeColor: Color
        let icon: String
    }

    var careAdvice: BatteryCareAdvice {
        let pct = snapshot.percent ?? 50
        let isChg = snapshot.charging == true
        let hasAC = snapshot.externalPower == true
        let limit = chargeLimit ?? 100

        if hasAC {
            if isChg {
                if pct < 80 {
                    return BatteryCareAdvice(
                        actionTitle: "充電中 · 建議充至 80%~85%",
                        actionTip: "目前電量 \(pct)%，建議保持 80%~85% 上限。充至 80% 即可滿足大半天，電芯內阻最低。",
                        cycleScience: "💡 循環知識：淺充不會多計 1 次循環！從 30% 充到 80%（僅耗 50% 額度），需充放兩次才算 1 個循環。隨用隨充比用完才充更能保護電極結構。",
                        badgeColor: .blue,
                        icon: "bolt.badge.checkmark.fill"
                    )
                } else {
                    return BatteryCareAdvice(
                        actionTitle: "已達黃金區間 · 旁路保護",
                        actionTip: "電量已達 \(pct)%，建議維持 80%~85% 上限。系統將自動切入電源旁路供電，電池完全免負擔！",
                        cycleScience: "💡 循環知識：當鎖在 80% 旁路供電時，電源線直接驅動主機板，電池不放電也不充電，循環計數器「完全靜止」！",
                        badgeColor: .green,
                        icon: "shield.lefthalf.filled"
                    )
                }
            } else {
                // On AC but not charging (e.g. at limit or 100%)
                if pct >= 98 && limit >= 98 {
                    return BatteryCareAdvice(
                        actionTitle: "100% 飽和高壓待機",
                        actionTip: "長期待在 100% 飽和狀態會使電芯處於 4.3V 高壓。若無需外出，強烈建議點擊「85% 限制」幫電池解壓。",
                        cycleScience: "💡 循環知識：長年插電 100% 待機雖然循環計數器增加極少，但持續高電壓（4.3V+）會加速電解液氧化分解。限制在 80%~85% 可延長 2~3 倍壽命。",
                        badgeColor: .orange,
                        icon: "exclamationmark.shield.fill"
                    )
                } else {
                    return BatteryCareAdvice(
                        actionTitle: "旁路供電保護中",
                        actionTip: "已在 \(pct)% 啟動保護，目前由外接電源直供系統運作，電芯處於超舒適的靜止休眠。",
                        cycleScience: "💡 循環知識：旁路模式下循環次數完全不增加，是保護電池健康的最佳狀態。",
                        badgeColor: .green,
                        icon: "checkmark.seal.fill"
                    )
                }
            }
        } else {
            // Discharging on battery
            if pct <= 20 {
                return BatteryCareAdvice(
                    actionTitle: "電量偏低 · 避免深度過放",
                    actionTip: "電量只剩 \(pct)%，建議盡快接上電源！鋰電池應避免低於 20%，過放會造成電極晶格永久損傷。",
                    cycleScience: "💡 增加循環的元兇：把電池「完全用乾到 0% 才充」是最傷的深度循環！深度過放會引發銅箔析出。在 20%~30% 就隨手補電能成倍延長壽命。",
                    badgeColor: .red,
                    icon: "battery.25"
                )
            } else if pct <= 45 {
                // e.g. 32% (User's specific case!)
                return BatteryCareAdvice(
                    actionTitle: "建議接電補至 80%（淺充保護）",
                    actionTip: "目前電量 \(pct)%，身旁若有電源，建議接上並充至 80%~85%。「淺充淺放」（30%~80%）能使電芯應力降到最低。",
                    cycleScience: "💡 循環知識：從 \(pct)% 充至 80% 僅累積 \((80 - pct))% 吞吐量，不會跳 1 次循環！累計滿 100% 才算一次循環，少吃多餐是長壽關鍵。",
                    badgeColor: .cyan,
                    icon: "arrow.up.heart.fill"
                )
            } else {
                return BatteryCareAdvice(
                    actionTitle: "健康放電中",
                    actionTip: "目前電量 \(pct)%，處於健康放電區間。出門請安心使用，降至 20%~30% 前再行補電即可。",
                    cycleScience: "💡 循環知識：放電是累計計算的（例：今日用 40%，明日用 60%，合起來才算第 1 次循環）。",
                    badgeColor: .purple,
                    icon: "leaf.fill"
                )
            }
        }
    }

    // MARK: - Smart Hardware Context Sensing & Gamification

    var chargerSpeedRating: (icon: String, text: String, color: Color) {
        guard snapshot.externalPower == true else {
            return ("battery.100", "電池供電中", .secondary)
        }
        let watts = snapshot.chargeWatts ?? 0
        if watts >= 55.0 {
            return ("bolt.fill", String(format: "滿血極速快充 (%.0fW)", watts), .green)
        } else if watts >= 18.0 {
            return ("bolt", String(format: "穩定常速充電 (%.0fW)", watts), .blue)
        } else if watts > 0 {
            return ("drop.fill", String(format: "微瓦慢充 (%.1fW)", watts), .orange)
        } else {
            return ("cable.connector", "旁路供電 (0W 待機)", .purple)
        }
    }

    var timeToLimitEstimate: String? {
        guard snapshot.charging == true, let watts = snapshot.chargeWatts, watts > 2.0 else { return nil }
        let currentPct = snapshot.percent ?? 50
        let targetLimit = displayChargeLimit
        guard currentPct < targetLimit else { return nil }

        let nominalWh: Double = 70.0
        let pctNeeded = Double(targetLimit - currentPct) / 100.0
        let neededWh = nominalWh * pctNeeded
        let hours = neededWh / watts
        let minutes = max(1, Int(hours * 60.0))
        if minutes >= 60 {
            return "\(minutes / 60) 小時 \(minutes % 60) 分"
        }
        return "\(minutes) 分鐘"
    }

    var isHighDischargeSpike: Bool {
        snapshot.externalPower == false && (snapshot.dischargeWatts ?? 0) >= 22.0
    }

    var continuousWorkMinutes: Int {
        Int(Date().timeIntervalSince(sessionStartTime) / 60.0)
    }

    struct GuardianLevel {
        let title: String
        let level: Int
        let stars: String
        let description: String
        let badgeColor: Color
    }

    var guardianLevel: GuardianLevel {
        var score = 0
        let pct = snapshot.percent ?? 50
        let temp = snapshot.temperature ?? 25.0
        let health = snapshot.healthPercent ?? 100.0

        if health >= 90.0 { score += 2 } else if health >= 80.0 { score += 1 }
        if displayChargeLimit <= 90 { score += 1 }
        if temp < 35.0 { score += 1 }
        if pct >= 20 { score += 1 }

        switch score {
        case 5:
            return GuardianLevel(title: "傳奇電芯守護神", level: 5, stars: "★★★★★", description: "完美保養習慣！電壓、溫度與上限控制無懈可擊！", badgeColor: .yellow)
        case 4:
            return GuardianLevel(title: "黃金電芯守護者", level: 4, stars: "★★★★☆", description: "保養得非常出色，電池正處於極長壽健康週期！", badgeColor: .green)
        case 3:
            return GuardianLevel(title: "進階能源護衛", level: 3, stars: "★★★☆☆", description: "用電習慣良好，記得避免溫度過高或長年 100% 待機。", badgeColor: .blue)
        case 2:
            return GuardianLevel(title: "初級電池夥伴", level: 2, stars: "★★☆☆☆", description: "建議開啟 85% 充電上限，並在電量降至 25% 前隨手補電。", badgeColor: .orange)
        default:
            return GuardianLevel(title: "新手電量見習生", level: 1, stars: "★☆☆☆☆", description: "請避免將電池用到 0% 關機，善用淺充淺放保護電芯！", badgeColor: .red)
        }
    }


    private func checkLimitNotifications(snapshot: BatterySnapshot) {
        guard let pct = snapshot.percent else { return }
        let isChg = snapshot.charging == true
        let limit = userTargetLimit

        if isChg, limit <= 90, pct >= limit {
            if lastNotifiedPct != pct {
                lastNotifiedPct = pct
                Self.postNotification(
                    title: "已達 \(limit)% 充電上限",
                    body: "硬體已限制充入電池，可保持插電或依需求拔除電源線。"
                )
            }
        } else if pct < 20 && snapshot.externalPower == false {
            if lastNotifiedPct != pct {
                lastNotifiedPct = pct
                Self.postNotification(
                    title: "電量過低警告（\(pct)%）",
                    body: "進入深度過放區域，建議儘速連接充電器以保護電芯壽命。"
                )
            }
        } else if pct >= 25 && pct <= 80 {
            lastNotifiedPct = nil
        }
    }

    nonisolated static func sendIMessage(target: String, content: String) -> (success: Bool, error: String?) {
        let cleanTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTarget.isEmpty else {
            return (false, "請先輸入接收者的電話號碼或 Apple ID 信箱")
        }
        let escapedTarget = cleanTarget.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let escapedContent = content.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let scriptText = """
        tell application "Messages"
            set targetService to 1st service whose service type = iMessage
            set targetBuddy to buddy "\(escapedTarget)" of targetService
            send "\(escapedContent)" to targetBuddy
        end tell
        """
        var errorDict: NSDictionary?
        if let script = NSAppleScript(source: scriptText) {
            script.executeAndReturnError(&errorDict)
            if let err = errorDict {
                let msg = err[NSAppleScript.errorMessage] as? String ?? "未知 AppleScript 錯誤"
                return (false, msg)
            }
            return (true, nil)
        }
        return (false, "無法建立 AppleScript 實例")
    }

    func sendTestIMessage() {
        let target = iPhoneIMessageTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }
        isTestingIMessage = true
        iMessageTestResult = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let testContent = "🔋【Mac 電池記錄器】iMessage 連線測試成功！\n當您的 Mac 充電達到目標電量時，將會自動發送即時推播通知至您的 iPhone。"
            let (success, err) = Self.sendIMessage(target: target, content: testContent)
            DispatchQueue.main.async {
                self?.isTestingIMessage = false
                if success {
                    self?.iMessageTestResult = (true, "已成功發送測試 iMessage 至 \(target)！請查看 iPhone 訊息。")
                } else {
                    self?.iMessageTestResult = (false, "發送失敗：\(err ?? "請確認 Messages 已登入 iMessage 且號碼正確")")
                }
            }
        }
    }

    private func checkIPhoneNotifications(snapshot: BatterySnapshot) {
        guard notifyIPhoneViaIMessage else { return }
        let target = iPhoneIMessageTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }

        let isAC = snapshot.externalPower == true
        if !isAC {
            notifiedIPhoneThresholds.removeAll()
            return
        }

        guard let pct = snapshot.percent else { return }
        let limit = userTargetLimit
        let tempStr = snapshot.temperature.map { String(format: "%.1f°C", $0) } ?? "正常"
        let healthStr = snapshot.healthPercent.map { String(format: "%.1f%%", $0) } ?? "良好"
        let cellDeltaStr = snapshot.cellImbalanceMv.map { "\($0) mV" } ?? "平衡"

        // 1. Check Charge Limit threshold (e.g. 80%, 85%, 90%)
        if (iPhoneNotifyThreshold == .atLimit || iPhoneNotifyThreshold == .both) && limit <= 95 {
            if pct >= limit && !notifiedIPhoneThresholds.contains(limit) {
                notifiedIPhoneThresholds.insert(limit)
                let msg = "🔋【Mac 電池提醒】已達 \(limit)% 充電上限！\n• 目前電量：\(pct)%\n• 電池溫度：\(tempStr)\n• 電芯壓差：\(cellDeltaStr)\n硬體已切換至保護狀態，可安心繼續插電或隨時拔除帶出門。"
                DispatchQueue.global(qos: .utility).async {
                    _ = Self.sendIMessage(target: target, content: msg)
                }
            }
        }

        // 2. Check 100% Full Charge threshold
        if iPhoneNotifyThreshold == .at100 || iPhoneNotifyThreshold == .both || (iPhoneNotifyThreshold == .atLimit && limit >= 100) {
            if pct >= 100 && !notifiedIPhoneThresholds.contains(100) {
                notifiedIPhoneThresholds.insert(100)
                let msg = "⚡️【Mac 電池提醒】電量已 100% 完全充飽！\n• 電池溫度：\(tempStr)\n• 健康度：\(healthStr)\n已充飽電，若不需出門建議適時拔掉充電線或開啟 85% 上限保護。"
                DispatchQueue.global(qos: .utility).async {
                    _ = Self.sendIMessage(target: target, content: msg)
                }
            }
        }
    }

    // MARK: - Intelligent Subsystems Implementation

    func handleSleepStart() {
        isSystemSleeping = true
        refreshTimer?.invalidate()
        refreshTimer = nil
        sleepStartTime = Date()
        sleepStartPct = snapshot.percent
        sleepStartTemp = snapshot.temperature
        UserDefaults.standard.set(sleepStartTime?.timeIntervalSince1970, forKey: "last_sleep_timestamp")
        UserDefaults.standard.set(sleepStartPct, forKey: "last_sleep_percent")
        UserDefaults.standard.set(sleepStartTemp, forKey: "last_sleep_temp")
    }

    func handleSleepWake() {
        isSystemSleeping = false
        if refreshTimer == nil {
            let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            timer.tolerance = 5.0
            RunLoop.main.add(timer, forMode: .common)
            refreshTimer = timer
        }
        let wakeTime = Date()
        let storedTs = UserDefaults.standard.double(forKey: "last_sleep_timestamp")
        let startTime = sleepStartTime ?? (storedTs > 0 ? Date(timeIntervalSince1970: storedTs) : nil)
        let startPct = sleepStartPct ?? UserDefaults.standard.integer(forKey: "last_sleep_percent")

        guard let start = startTime, startPct > 0 else { return }
        let durationSec = max(1, wakeTime.timeIntervalSince(start))
        let hours = durationSec / 3600.0
        let currentPct = snapshot.percent ?? startPct
        let pctDrop = max(0, startPct - currentPct)
        let endTemp = snapshot.temperature ?? 25.0

        var advice = "電芯處於超低功耗休眠，睡眠守護良好。"
        var isSafe = true
        if pctDrop >= 5 || (hours > 0 && (Double(pctDrop) / hours) > 1.5) {
            advice = "⚠️ 睡眠期間耗電偏高，建議檢查是否有藍牙設備或背景程式喚醒。"
            isSafe = false
        } else if endTemp >= 35.0 {
            advice = "🔥 喚醒時機身溫度偏高（\(String(format: "%.1f°C", endTemp))），放入電腦包前請確認已完全進入深度睡眠，防範背包悶燒！"
            isSafe = false
        }

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd HH:mm"
        let report = SleepGuardianReport(
            date: dateFmt.string(from: wakeTime),
            durationHours: hours,
            drainPercent: pctDrop,
            wakeTemperature: endTemp,
            isSafe: isSafe,
            summary: advice
        )
        self.lastSleepReport = report

        if voicePromptEnabled {
            let isIronMan = buddySkin == .arcReactor
            let greet = isIronMan ?
                "Good morning, Sir. Systems active. Sleep drain was \(pctDrop) percent." :
                "長官您好，Mac 已喚醒。睡眠期間耗損 \(pctDrop)%，目前電量 \(currentPct)%。"
            VoicePromptManager.shared.speak(text: greet, isJarvis: isIronMan)
        }

        sleepStartTime = nil
        sleepStartPct = nil
        sleepStartTemp = nil
        UserDefaults.standard.removeObject(forKey: "last_sleep_timestamp")
    }

    func checkCalendarOutings() {
        guard calendarOutingPredictionEnabled else {
            self.calendarOutingAlert = nil
            return
        }
        Task { @MainActor in
            if let alert = await CalendarOutingPredictor.shared.checkUpcomingOuting() {
                self.calendarOutingAlert = alert
                if self.voicePromptEnabled {
                    let eventKey = "announced_calendar_\(alert.id)"
                    if !UserDefaults.standard.bool(forKey: eventKey) {
                        UserDefaults.standard.set(true, forKey: eventKey)
                        let isIronMan = self.buddySkin == .arcReactor
                        let text = isIronMan ?
                            "Sir, calendar alert: You have '\(alert.title)' scheduled at \(alert.timeDescription). I recommend Boost Mode to charge to 100%." :
                            "提醒長官：行事曆偵測到「\(alert.title)」即將於 \(alert.timeDescription)。建議開啟衝刺模式充至 100% 以備外出！"
                        VoicePromptManager.shared.speak(text: text, isJarvis: isIronMan)
                    }
                }
            } else {
                self.calendarOutingAlert = nil
            }
        }
    }

    func checkEnergyVampires(snapshot: BatterySnapshot) {
        guard !isSystemSleeping else { return }
        guard rogueVampireDetectionEnabled else {
            topEnergyVampires = []
            isRogueDrainAlert = false
            return
        }

        guard snapshot.externalPower == false else {
            if isRogueDrainAlert {
                isRogueDrainAlert = false
                topEnergyVampires = []
            }
            return
        }

        let now = Date()
        if let lastScan = lastVampireScanTime, now.timeIntervalSince(lastScan) < 8.0 {
            return
        }
        lastVampireScanTime = now

        let watts = snapshot.dischargeWatts ?? 0.0
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let vampires = EnergyVampireDetective.scanTopEnergyVampires()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.topEnergyVampires = vampires
                if let top = vampires.first, top.cpuPercent >= 25.0, watts >= 14.0 {
                    self.isRogueDrainAlert = true
                    self.rogueDrainWatts = watts

                    let lastVampireVoiceKey = "last_vampire_voice_pid"
                    let lastPid = UserDefaults.standard.integer(forKey: lastVampireVoiceKey)
                    if self.voicePromptEnabled && lastPid != top.id {
                        UserDefaults.standard.set(top.id, forKey: lastVampireVoiceKey)
                        let isIronMan = self.buddySkin == .arcReactor
                        let text = isIronMan ?
                            "Warning, Sir. Energy vampire detected: \(top.name) is drawing excessive power at \(String(format: "%.0f", top.cpuPercent)) percent CPU." :
                            "注意：偵測到「\(top.name)」正在劇烈耗電（佔用 \(String(format: "%.0f", top.cpuPercent))% CPU），放電功率達 \(String(format: "%.1f", watts)) 瓦！"
                        VoicePromptManager.shared.speak(text: text, isJarvis: isIronMan)
                    }
                } else {
                    self.isRogueDrainAlert = false
                }
            }
        }
    }

    func terminateVampireApp(pid: Int) {
        if let running = NSRunningApplication(processIdentifier: pid_t(pid)) {
            running.terminate()
        } else {
            kill(pid_t(pid), SIGTERM)
        }
        topEnergyVampires.removeAll(where: { $0.id == pid })
        if topEnergyVampires.isEmpty || (topEnergyVampires.first?.cpuPercent ?? 0) < 25.0 {
            isRogueDrainAlert = false
        }
    }

    private var lastAnnouncedACState: Bool?
    private var lastAnnouncedLimitReached: Int?
    private var lastAnnouncedLowBattery = false

    func triggerVoicePrompts(snapshot: BatterySnapshot) {
        guard voicePromptEnabled else { return }
        let isIronMan = buddySkin == .arcReactor

        // 1. AC plugged in / unplugged
        if let isAC = snapshot.externalPower {
            if let lastAC = lastAnnouncedACState {
                if lastAC == false && isAC == true {
                    let text = isIronMan ? "Power grid connected. Arc Reactor charging online." : "電源已連接，正在為 Mac 充電與供電。"
                    VoicePromptManager.shared.speak(text: text, isJarvis: isIronMan)
                } else if lastAC == true && isAC == false {
                    let text = isIronMan ? "Power disconnected. Running on internal Arc energy." : "電源已拔除，切換至電池供電模式。"
                    VoicePromptManager.shared.speak(text: text, isJarvis: isIronMan)
                }
            }
            lastAnnouncedACState = isAC
        }

        // 2. Limit reached (e.g. 80%, 85%, 90%)
        if let pct = snapshot.percent {
            let limit = userTargetLimit
            if snapshot.externalPower == true && pct >= limit && limit <= 95 {
                if lastAnnouncedLimitReached != limit {
                    lastAnnouncedLimitReached = limit
                    let text = isIronMan ?
                        "Target charge capacity of \(limit) percent reached, Sir. Hardware bypass engaged." :
                        "報告長官，電量已達設定的 \(limit)% 上限，硬體已自動切換為旁路保護。"
                    VoicePromptManager.shared.speak(text: text, isJarvis: isIronMan)
                }
            } else if pct < limit - 5 {
                lastAnnouncedLimitReached = nil
            }
        }

        // 3. Low Battery warning
        if let pct = snapshot.percent, snapshot.externalPower == false {
            if pct <= 20 && !lastAnnouncedLowBattery {
                lastAnnouncedLowBattery = true
                let text = isIronMan ?
                    "Warning: Energy reserves down to \(pct) percent. Recommend docking immediately." :
                    "電量偏低警告：目前電量僅剩 \(pct)%，建議盡快連接充電器以保護電芯壽命。"
                VoicePromptManager.shared.speak(text: text, isJarvis: isIronMan)
            } else if pct >= 25 {
                lastAnnouncedLowBattery = false
            }
        }
    }

    // MARK: - Gemini AI Methods

    func askGemini(customPrompt: String? = nil) {
        let text = (customPrompt ?? geminiAiQuery).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isGeminiQuerying = true
        geminiChatHistory.append((isUser: true, text: text))
        geminiAiQuery = ""

        let snap = self.snapshot
        let skin = self.buddySkin
        let vampires = self.topEnergyVampires
        let limit = self.displayChargeLimit

        Task { @MainActor in
            let response = await GeminiService.shared.generateResponse(
                prompt: text,
                snapshot: snap,
                skin: skin,
                topVampires: vampires,
                limit: limit
            )
            self.geminiAiResponse = response
            self.geminiChatHistory.append((isUser: false, text: response))
            self.isGeminiQuerying = false
        }
    }

    func requestGeminiDiagnosticReport() {
        askGemini(customPrompt: "請結合我這台 Mac 目前的型號、SOH健康度、循環次數、電芯壓差、即時放電瓦數與溫度，為我進行一次深度的電化學健康評估。列出：1. 當前健康評級 2. 潛在風險點 3. 客製化保養與充電上限建議 4. 二手轉售價值維護指南。請以清晰條列呈現。")
    }

    func setChargeLimit(_ newLimit: Int) {
        if isAppleSilicon {
            self.limitMessage = "Apple Silicon 機型無 Intel SMC (BCLM) 限充暫存器，建議使用系統內建最佳化充電。"
            self.errorMessage = "Apple Silicon 機型不支援 Intel SMC (BCLM) 限充暫存器。"
            return
        }
        if newLimit >= 60 {
            userTargetLimit = newLimit
            UserDefaults.standard.set(newLimit, forKey: "userTargetLimit")
            isSailingPaused = false
            isDischargeOnACActive = false
        }
        writeSMCHardwareLimit(newLimit)
    }

    func writeSMCHardwareLimit(_ newLimit: Int) {
        guard !isSettingLimit else { return }
        isSettingLimit = true
        limitMessage = "正在設定 \(newLimit)% 硬體上限…"

        Task.detached(priority: .userInitiated) {
            var toolPath: String?
            if FileManager.default.fileExists(atPath: "/usr/local/bin/smc-battery-tool") {
                toolPath = "/usr/local/bin/smc-battery-tool"
            } else if let bundled = Bundle.main.url(forResource: "smc-battery-tool", withExtension: nil)?.path,
               FileManager.default.fileExists(atPath: bundled) {
                toolPath = bundled
            } else {
                let candidates = [
                    "/Applications/Battery Logger.app/Contents/Resources/smc-battery-tool",
                    URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/smc-battery-tool").path,
                    "/tmp/smc_battery_tool_universal",
                    "/tmp/smc_battery_tool"
                ]
                toolPath = candidates.first(where: { FileManager.default.fileExists(atPath: $0) })
            }

            guard let tool = toolPath else {
                await MainActor.run {
                    self.isSettingLimit = false
                    self.limitMessage = "找不到 smc-battery-tool 輔助工具"
                    self.errorMessage = "找不到 smc-battery-tool 輔助工具，請確認 App 是否完整安裝。"
                }
                return
            }

            // 1. Try direct execution
            let direct = Process()
            direct.executableURL = URL(fileURLWithPath: tool)
            direct.arguments = ["write", "\(newLimit)"]
            let pipe = Pipe()
            direct.standardOutput = pipe
            direct.standardError = pipe
            try? direct.run()
            direct.waitUntilExit()

            var success = direct.terminationStatus == 0

            // 2. If privileges required, prompt via AppleScript
            if !success {
                let prompt = newLimit == 100
                    ? "Battery Logger 想要解除充電限制，充至 100%（外出模式）："
                    : "Battery Logger 想要設定硬體充電上限為 \(newLimit)%："
                let script = "do shell script quoted form of \"\(tool)\" & \" write \(newLimit)\" with prompt \"\(prompt)\" with administrator privileges"
                var errDict: NSDictionary?
                let res = NSAppleScript(source: script)?.executeAndReturnError(&errDict)
                success = res != nil && errDict == nil
            }

            let finalSuccess = success
            await MainActor.run {
                self.isSettingLimit = false
                if finalSuccess {
                    self.refresh()
                    let msg = newLimit == 100 ? "已解除限制，允許充至 100%（外出模式）" : "已成功設定硬體充電上限為 \(newLimit)%"
                    self.limitMessage = msg
                    Self.postNotification(title: "電池保養設定更新", body: msg)
                } else {
                    self.limitMessage = "設定失敗：未授權或硬體不支援"
                    self.errorMessage = "無法設定充電上限：需要管理員授權以寫入 SMC 暫存器。"
                }
            }
        }
    }

    nonisolated static func postNotification(title: String, body: String) {
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedBody = body.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "display notification \"\(escapedBody)\" with title \"\(escapedTitle)\" sound name \"default\""
        NSAppleScript(source: script)?.executeAndReturnError(nil)
    }

    func startRecording() {
        guard !recording else { return }
        do {
            let folder = try FileManager.default.url(for: .applicationSupportDirectory,
                                                      in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Battery Logger", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let file = folder.appendingPathComponent("battery-\(stamp).csv")
            FileManager.default.createFile(atPath: file.path, contents: nil)
            logHandle = try FileHandle(forWritingTo: file)
            logHandle?.write(Data("timestamp,model,macOS,build,battery_percent,capacity_mAh,full_capacity_mAh,voltage_mV,current_mA,discharge_W,cumulative_discharge_Wh,cycles,temperature_C,condition,external_power,charging,event,battery_power_W,cpu_temperature_C\n".utf8))
            logPath = file.path
            cumulativeWh = 0
            previous = nil
            recording = true
            sampleAndLog(event: "sample")
            timer = Timer.scheduledTimer(withTimeInterval: sampleInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.sampleAndLog(event: "sample") }
            }
        } catch {
            errorMessage = "無法建立記錄檔：\(error.localizedDescription)"
        }
    }

    func stopRecording() {
        timer?.invalidate()
        timer = nil
        try? logHandle?.close()
        logHandle = nil
        recording = false
        previous = nil
    }

    func openActivityMonitor() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
    }

    func openLogFolder() {
        guard let folder = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                        appropriateFor: nil, create: true)
            .appendingPathComponent("Battery Logger", isDirectory: true) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            syncLaunchAtLoginStatus()
            if launchAtLoginNeedsApproval {
                launchAtLoginMessage = "已加入登入項目，請在系統設定中允許 Battery Logger。"
            } else {
                launchAtLoginMessage = enabled ? "已設定登入時自動啟動。" : "已關閉登入時自動啟動。"
            }
        } catch {
            syncLaunchAtLoginStatus()
            launchAtLoginMessage = "設定失敗：\(error.localizedDescription)"
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func syncLaunchAtLoginStatus() {
        let status = SMAppService.mainApp.status
        launchAtLoginEnabled = status == .enabled || status == .requiresApproval
        launchAtLoginNeedsApproval = status == .requiresApproval
    }

    func chooseComparisonFile(_ slot: Int) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "選取 Battery Logger 匯出的 CSV 記錄"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if slot == 0 { comparisonFileA = url.path } else { comparisonFileB = url.path }
        if !comparisonFileA.isEmpty && !comparisonFileB.isEmpty { compareSessions() }
    }

    func compareSessions() {
        do {
            let a = try Self.summarizeCSV(at: URL(fileURLWithPath: comparisonFileA))
            let b = try Self.summarizeCSV(at: URL(fileURLWithPath: comparisonFileB))
            compareResult = Self.comparisonText(a, b)
        } catch {
            errorMessage = "讀取比較記錄失敗：\(error.localizedDescription)"
        }
    }

    private func recordPowerEvent(_ event: String) {
        guard recording else { return }
        sampleAndLog(event: event)
        try? logHandle?.synchronize()
    }

    private func sampleAndLog(event: String) {
        var value = Self.readBatterySnapshot()
        if let details = systemDetails {
            value.model = details.model
            value.processor = details.processor
            value.memory = details.memory
            value.macOS = details.macOS
            value.build = details.build
            value.condition = details.condition
        }
        snapshot = value
        let now = Date()
        let onBattery = value.externalPower == false
        let watts = value.dischargeWatts ?? 0
        if let previous, onBattery, previous.onBattery {
            let elapsed = now.timeIntervalSince(previous.time)
            if elapsed <= sampleInterval * 2.2 {
                cumulativeWh += (watts + previous.watts) / 2 * elapsed / 3600
            }
        }
        previous = (now, watts, onBattery)
        let cells: [String] = [
            ISO8601DateFormatter().string(from: now), value.model, value.macOS, value.build,
            value.percent.map { String($0) } ?? "", value.capacity.map { String($0) } ?? "",
            value.fullCapacity.map { String($0) } ?? "", value.voltage.map { String($0) } ?? "",
            value.current.map { String($0) } ?? "", String(format: "%.4f", watts),
            String(format: "%.5f", cumulativeWh), value.cycles.map { String($0) } ?? "",
            value.temperature.map { String(format: "%.1f", $0) } ?? "", value.condition,
            value.externalPower.map { String($0) } ?? "", value.charging.map { String($0) } ?? "", event,
            value.batteryPowerWatts.map { String(format: "%.4f", $0) } ?? "",
            value.cpuTemperature.map { String(format: "%.1f", $0) } ?? ""
        ]
        let row = cells.map { Self.csvEscape($0) }.joined(separator: ",") + "\n"
        logHandle?.write(Data(row.utf8))
    }

    private static func csvEscape(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    nonisolated private static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = [], field = "", quoted = false
        var chars = Array(line), i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                if quoted && i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 }
                else { quoted.toggle() }
            } else if c == "," && !quoted { fields.append(field); field = "" }
            else { field.append(c) }
            i += 1
        }
        fields.append(field)
        return fields
    }

    nonisolated private static func summarizeCSV(at url: URL) throws -> LogSummary {
        let contents = try String(contentsOf: url, encoding: .utf8)
        let lines = contents.split(whereSeparator: \.isNewline).map(String.init)
        guard let headerLine = lines.first else { throw NSError(domain: "BatteryLogger", code: 1, userInfo: [NSLocalizedDescriptionKey: "CSV 是空的"]) }
        let header = parseCSVLine(headerLine)
        let indices = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })
        func value(_ row: [String], _ key: String) -> String? {
            guard let i = indices[key], i < row.count, !row[i].isEmpty else { return nil }
            return row[i]
        }
        let formatter = ISO8601DateFormatter()
        var records: [(row: [String], date: Date)] = []
        var sleepStart: Date?, sleepSeconds: TimeInterval = 0
        for line in lines.dropFirst() {
            let row = parseCSVLine(line)
            guard let stamp = value(row, "timestamp"), let date = formatter.date(from: stamp) else { continue }
            records.append((row, date))
            if value(row, "event") == "sleep" { sleepStart = date }
            if value(row, "event") == "wake", let start = sleepStart {
                sleepSeconds += max(0, date.timeIntervalSince(start)); sleepStart = nil
            }
        }
        guard let first = records.first, let last = records.last else {
            throw NSError(domain: "BatteryLogger", code: 2, userInfo: [NSLocalizedDescriptionKey: "找不到可用的電池取樣資料"])
        }
        let firstCumulative = value(first.row, "cumulative_discharge_Wh").flatMap(Double.init)
        let lastCumulative = value(last.row, "cumulative_discharge_Wh").flatMap(Double.init)
        let wh = (firstCumulative != nil && lastCumulative != nil) ? max(0, lastCumulative! - firstCumulative!) : nil
        return LogSummary(path: url.lastPathComponent,
                          model: value(first.row, "model") ?? "未知 Mac",
                          macOS: value(first.row, "macOS") ?? "未知 macOS",
                          start: first.date, end: last.date,
                          startPercent: value(first.row, "battery_percent").flatMap(Int.init),
                          endPercent: value(last.row, "battery_percent").flatMap(Int.init),
                          startCapacity: value(first.row, "capacity_mAh").flatMap(Int.init),
                          endCapacity: value(last.row, "capacity_mAh").flatMap(Int.init),
                          awakeWh: wh, sleepSeconds: sleepSeconds)
    }

    nonisolated private static func comparisonText(_ a: LogSummary, _ b: LogSummary) -> String {
        func duration(_ interval: TimeInterval) -> String {
            let minutes = Int(interval / 60)
            return "\(minutes / 60) 小時 \(minutes % 60) 分"
        }
        func summary(_ item: LogSummary) -> String {
            let pctDrop: String = if let start = item.startPercent, let end = item.endPercent { "\(start - end)%" } else { "—" }
            let capacityDrop: String = if let start = item.startCapacity, let end = item.endCapacity { "\(start - end) mAh" } else { "—" }
            let wh = item.awakeWh.map { String(format: "%.3f Wh（清醒期間估算）", $0) } ?? "舊格式記錄，無 Wh 欄位"
            return "\(item.macOS) · \(item.model)\n\(item.start.formatted(date: .numeric, time: .shortened)) – \(item.end.formatted(date: .numeric, time: .shortened))（\(duration(item.end.timeIntervalSince(item.start)))）\n電量下降：\(pctDrop)　容量下降：\(capacityDrop)\n\(wh)　合蓋睡眠：\(duration(item.sleepSeconds))"
        }
        return "記錄 A：\n\(summary(a))\n\n記錄 B：\n\(summary(b))\n\n比較提示：Wh 是 app 在 Mac 清醒且取樣連續時的放電估算；合蓋睡眠的消耗請以睡前、喚醒後容量差為主。盡量讓兩次測試時長、起始電量、亮度、網路與背景程式一致。"
    }

    nonisolated private static func run(_ executable: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe
        defer {
            try? pipe.fileHandleForReading.close()
            try? pipe.fileHandleForWriting.close()
            try? errPipe.fileHandleForReading.close()
            try? errPipe.fileHandleForWriting.close()
        }
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch { return "" }
    }

    nonisolated private static func key(_ name: String, in text: String) -> String? {
        let pattern = "(?m)^\\s+\"\(NSRegularExpression.escapedPattern(for: name))\"\\s*=\\s*(.+?)\\s*$"
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        let line = String(text[range])
        guard let equal = line.firstIndex(of: "=") else { return nil }
        return line[line.index(after: equal)...].trimmingCharacters(in: .whitespaces)
    }

    nonisolated private static func integer(_ name: String, in text: String, signed: Bool = false) -> Int? {
        guard let raw = key(name, in: text), let number = UInt64(raw) else { return nil }
        if signed && number >= (1 << 63) { return Int(truncatingIfNeeded: number) }
        return Int(exactly: number)
    }

    nonisolated private static func sysctl(_ name: String) -> String {
        run("/usr/sbin/sysctl", ["-n", name]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func readSystemDetails() -> SystemDetails {
        var details = SystemDetails()
        details.model = sysctl("hw.model")
        details.processor = sysctl("machdep.cpu.brand_string")
        if let bytes = UInt64(sysctl("hw.memsize")) {
            details.memory = String(format: "%.0f GB", Double(bytes) / 1_073_741_824)
        }
        details.macOS = run("/usr/bin/sw_vers", ["-productVersion"]).trimmingCharacters(in: .whitespacesAndNewlines)
        details.build = run("/usr/bin/sw_vers", ["-buildVersion"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let profiler = run("/usr/sbin/system_profiler", ["SPPowerDataType"])
        if let match = profiler.range(of: #"Condition: .*"#, options: .regularExpression) {
            details.condition = String(profiler[match]).replacingOccurrences(of: "Condition: ", with: "")
        }
        return details
    }

    nonisolated private static func readBatterySnapshot() -> BatterySnapshot {
        var result = BatterySnapshot()
        let seconds = Int(ProcessInfo.processInfo.systemUptime)
        result.uptime = "\(seconds / 86400) 天 \((seconds % 86400) / 3600) 小時 \((seconds % 3600) / 60) 分"

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        var batteryDict: [String: Any]?
        if service != IO_OBJECT_NULL {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any] {
                batteryDict = dict
            }
            IOObjectRelease(service)
        }

        func intVal(_ key: String) -> Int? {
            guard let batteryDict, let val = batteryDict[key] else { return nil }
            if let n = val as? NSNumber { return n.intValue }
            if let i = val as? Int { return i }
            return nil
        }

        func strVal(_ key: String) -> String? {
            guard let batteryDict, let val = batteryDict[key] else { return nil }
            if let s = val as? String { return s }
            return nil
        }

        func boolVal(_ key: String) -> Bool? {
            guard let batteryDict, let val = batteryDict[key] else { return nil }
            if let b = val as? Bool { return b }
            if let n = val as? NSNumber { return n.boolValue }
            if let s = val as? String { return s == "Yes" || s == "true" }
            return nil
        }

        result.capacity = intVal("CurrentCapacity")
        result.fullCapacity = intVal("MaxCapacity")
        result.designCapacity = intVal("DesignCapacity")
        result.voltage = intVal("Voltage")
        result.current = intVal("Amperage")
        result.cycles = intVal("CycleCount")
        result.cpuTemperature = readCPUTemperature()
        result.timeRemaining = intVal("TimeRemaining")
        result.maxError = intVal("MaxErr")
        if let raw = strVal("Manufacturer") {
            result.manufacturer = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        if let raw = strVal("DeviceName") {
            result.controllerModel = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        if let rawTemp = intVal("Temperature") {
            result.temperature = Double(rawTemp) / 100.0
        }
        result.externalPower = boolVal("ExternalConnected")
        result.charging = boolVal("IsCharging")
        result.fullyCharged = boolVal("FullyCharged")
        result.externalChargeCapable = boolVal("ExternalChargeCapable")
        if let raw = strVal("Serial") {
            result.serialNumber = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        result.permanentFailureStatus = intVal("PermanentFailureStatus")

        // Parse BatteryData sub-dictionary for UISoc, CellVoltage, Qmax
        if let batteryData = batteryDict?["BatteryData"] as? [String: Any] {
            if let uisoc = batteryData["UISoc"] as? Int {
                result.percent = uisoc
            } else if let uisocNum = batteryData["UISoc"] as? NSNumber {
                result.percent = uisocNum.intValue
            }
            if let cellArray = batteryData["CellVoltage"] as? [Int] {
                result.cellVoltages = cellArray
            } else if let cellNums = batteryData["CellVoltage"] as? [NSNumber] {
                result.cellVoltages = cellNums.map { $0.intValue }
            }
            if let qmaxArray = batteryData["Qmax"] as? [Int] {
                result.qmax = qmaxArray
            } else if let qmaxNums = batteryData["Qmax"] as? [NSNumber] {
                result.qmax = qmaxNums.map { $0.intValue }
            }
        }

        // Parse AdapterDetails
        if let adapterDetails = batteryDict?["AdapterDetails"] as? [String: Any] {
            if let w = adapterDetails["Watts"] as? Int { result.adapterWatts = w }
            else if let wn = adapterDetails["Watts"] as? NSNumber { result.adapterWatts = wn.intValue }
            if let v = adapterDetails["AdapterVoltage"] as? Int { result.adapterVoltageMv = v }
            else if let vn = adapterDetails["AdapterVoltage"] as? NSNumber { result.adapterVoltageMv = vn.intValue }
            if let c = adapterDetails["Current"] as? Int { result.adapterCurrentMa = c }
            else if let cn = adapterDetails["Current"] as? NSNumber { result.adapterCurrentMa = cn.intValue }
        }

        // Read power sources directly from IOKit.ps for instant and accurate state
        var iopsCharging: Bool?
        var iopsExternalPower: Bool?
        var iopsFullyCharged: Bool?
        var iopsPercent: Int?

        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for item in list {
                guard let desc = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any] else { continue }
                if let val = desc[kIOPSIsChargingKey] {
                    if let b = val as? Bool { iopsCharging = b }
                    else if let n = val as? NSNumber { iopsCharging = n.boolValue }
                }
                if let state = desc[kIOPSPowerSourceStateKey] as? String {
                    if state == kIOPSACPowerValue { iopsExternalPower = true }
                    else if state == kIOPSBatteryPowerValue { iopsExternalPower = false }
                }
                if let val = desc[kIOPSIsChargedKey] {
                    if let b = val as? Bool { iopsFullyCharged = b }
                    else if let n = val as? NSNumber { iopsFullyCharged = n.boolValue }
                }
                if let cap = desc[kIOPSCurrentCapacityKey] as? Int {
                    iopsPercent = cap
                }
            }
        }

        if result.percent == nil {
            if let iopsPercent {
                result.percent = iopsPercent
            } else if let cur = result.capacity, let maxCap = result.fullCapacity, maxCap > 0 {
                result.percent = Swift.min(100, Swift.max(0, Int(Double(cur) / Double(maxCap) * 100.0)))
            }
        }

        if let iopsExternalPower {
            result.externalPower = iopsExternalPower
        }

        let isHardwareCharging = iopsCharging == true || result.charging == true || ((result.current ?? 0) > 50)
        let isFullyChargedSignal = iopsFullyCharged == true || result.fullyCharged == true
        result.fullyCharged = isFullyChargedSignal && ((result.percent ?? 0) >= 95)

        if result.externalPower == true {
            if result.fullyCharged == true || (result.percent ?? 0) == 100 {
                result.charging = false
            } else if isHardwareCharging {
                result.charging = true
            } else {
                result.charging = false
            }
        } else {
            result.charging = false
        }

        var smcLimit: Int32 = 0
        if BatteryLoggerReadChargeLimit(&smcLimit) == 1 && smcLimit >= 50 && smcLimit <= 100 {
            result.chargeLimit = Int(smcLimit)
        } else {
            result.chargeLimit = nil
        }

        result.updated = Date()
        return result
    }

    nonisolated private static func readCPUTemperature() -> Double? {
        var value: Double = 0
        guard BatteryLoggerReadCPUTemperature(&value) == 1,
              value.isFinite, (0...120).contains(value) else { return nil }
        return value
    }
}

@_silgen_name("BatteryLoggerReadCPUTemperature")
private func BatteryLoggerReadCPUTemperature(_ value: UnsafeMutablePointer<Double>) -> Int32

@_silgen_name("BatteryLoggerReadChargeLimit")
private func BatteryLoggerReadChargeLimit(_ value: UnsafeMutablePointer<Int32>) -> Int32

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

/// An NSImage subclass that overrides `isTemplate` so SwiftUI's MenuBarExtra cannot force it into monochrome template mode.
final class NonTemplateImage: NSImage {
    override var isTemplate: Bool {
        get { false }
        set { /* No-op: Prevent SwiftUI from converting to monochrome template */ }
    }
}

/// Renders a non-template NSImage so macOS MenuBarExtra displays vivid real colors.
@MainActor
enum MenuBarIconRenderer {
    static func render(snapshot: BatterySnapshot, isCharging: Bool, isDischarging: Bool, isFullyCharged: Bool, isDark: Bool, mode: MenuBarDisplayMode = .iconAndPercent) -> NSImage {
        let pct = snapshot.percent ?? 0
        let temp = snapshot.temperature ?? 25.0

        // Multi-tier color hierarchy for high visibility and clear recognition:
        let color: NSColor
        if temp >= 36.5 {
            color = NSColor(srgbRed: 0.95, green: 0.23, blue: 0.23, alpha: 1.0)
        } else if isCharging {
            color = NSColor(srgbRed: 0.18, green: 0.82, blue: 0.35, alpha: 1.0)
        } else {
            if pct >= 85 {
                color = NSColor(srgbRed: 0.18, green: 0.82, blue: 0.35, alpha: 1.0)
            } else if pct >= 60 {
                color = NSColor(srgbRed: 0.0, green: 0.68, blue: 0.95, alpha: 1.0)
            } else if pct >= 35 {
                color = NSColor(srgbRed: 0.98, green: 0.72, blue: 0.05, alpha: 1.0)
            } else if pct >= 21 {
                color = NSColor(srgbRed: 1.0, green: 0.55, blue: 0.08, alpha: 1.0)
            } else {
                color = NSColor(srgbRed: 0.95, green: 0.23, blue: 0.23, alpha: 1.0)
            }
        }

        let isDarkMode = isDark
        // Native solid menu bar text: Pure solid white in dark mode, pure solid black in light mode
        let textSolidColor: NSColor = isDarkMode ? .white : .black
        // Battery capsule frame dynamically follows macOS native styling
        let frameStrokeColor: NSColor = textSolidColor.withAlphaComponent(isDarkMode ? 0.48 : 0.38)

        let textStr: String
        if mode == .iconAndRemainingTime {
            if let time = snapshot.timeRemaining, time > 0, time < 1440 {
                textStr = "\(time / 60):\(String(format: "%02d", time % 60))"
            } else {
                textStr = snapshot.percent.map { "\($0)%" } ?? "—%"
            }
        } else {
            textStr = snapshot.percent.map { "\($0)%" } ?? "—%"
        }

        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textSolidColor
        ]
        let attrStr = NSAttributedString(string: textStr, attributes: textAttrs)
        let textSize = attrStr.size()
        let batteryWidth: CGFloat = 29
        let spacing: CGFloat = 4
        let totalHeight: CGFloat = 22

        let totalWidth: CGFloat
        switch mode {
        case .iconOnly:
            totalWidth = batteryWidth + 2
        case .percentOnly:
            totalWidth = ceil(textSize.width) + 4
        case .iconAndPercent, .iconAndRemainingTime:
            totalWidth = ceil(batteryWidth + spacing + textSize.width + 4)
        }

        let symbolName: String? = isCharging ? "bolt.fill" : (!isDischarging ? "powerplug.fill" : nil)
        let symbol = symbolName.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
                .applying(.init(paletteColors: [textSolidColor])))

        let image = NonTemplateImage(size: NSSize(width: totalWidth, height: totalHeight), flipped: false) { _ in
            let shouldDrawBattery = mode != .percentOnly
            let shouldDrawText = mode != .iconOnly

            if shouldDrawBattery {
                let body = NSRect(x: 1.5, y: 4.5, width: 26, height: 13)
                let frame = NSBezierPath(roundedRect: body, xRadius: 2.8, yRadius: 2.8)
                frame.lineWidth = 0.85
                frameStrokeColor.setStroke()
                frame.stroke()

                // A short rounded terminal, matching the body outline weight.
                let terminal = NSBezierPath()
                terminal.move(to: NSPoint(x: body.maxX + 1.2, y: 8.8))
                terminal.curve(to: NSPoint(x: body.maxX + 1.2, y: 13.2),
                               controlPoint1: NSPoint(x: body.maxX + 2.3, y: 8.8),
                               controlPoint2: NSPoint(x: body.maxX + 2.3, y: 13.2))
                terminal.lineWidth = 0.85
                terminal.lineCapStyle = .round
                frameStrokeColor.setStroke()
                terminal.stroke()

                let interior = body.insetBy(dx: 1.7, dy: 1.7)
                let fillWidth = interior.width * CGFloat(max(0, min(100, pct))) / 100
                if fillWidth > 0 {
                    NSGraphicsContext.saveGraphicsState()
                    NSBezierPath(roundedRect: interior, xRadius: 1.2, yRadius: 1.2).addClip()
                    color.setFill()
                    NSRect(x: interior.minX, y: interior.minY, width: fillWidth, height: interior.height).fill()
                    NSGraphicsContext.restoreGraphicsState()
                }
                if let symbol {
                    let size = symbol.size
                    symbol.draw(in: NSRect(x: body.midX - size.width / 2,
                                           y: body.midY - size.height / 2,
                                           width: size.width, height: size.height))
                }
            }

            if shouldDrawText {
                let textX: CGFloat = (mode == .percentOnly) ? 2 : (batteryWidth + spacing + 1)
                attrStr.draw(in: NSRect(x: textX,
                                       y: round((totalHeight - textSize.height) / 2),
                                       width: ceil(textSize.width) + 1, height: ceil(textSize.height)))
            }
            return true
        }

        image.isTemplate = false
        return image
    }
}

/// Observes battery data directly so the menu bar label redraws on every snapshot.
private struct MenuBarStatusLabel: View {
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

enum DashboardTab: String, CaseIterable, Identifiable {
    case overview = "⚡️ 能源概覽"
    case intelligence = "🧠 智能守護與 AI"
    case diagnostics = "🔬 深度技術與分析"

    var id: String { rawValue }
}

struct DashboardView: View {
    @EnvironmentObject private var model: BatteryModel
    @Environment(\.openWindow) private var openWindow
    @State private var selectedTab: DashboardTab = .overview
    @State private var showingBatteryDetails = false
    @State private var showingKnowledge = false
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(spacing: 0) {
            dashboardHeaderView
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 10)

            Picker("分頁選擇", selection: $selectedTab) {
                ForEach(DashboardTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedTab {
                    case .overview:
                        overviewTab
                    case .intelligence:
                        intelligenceTab
                    case .diagnostics:
                        diagnosticsTab
                    }

                    Spacer(minLength: 0)
                    footerView
                }
                .padding(20)
            }
        }
        .alert("發生問題", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("好", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .sheet(isPresented: $showingBatteryDetails) {
            BatteryDetailsView(snapshot: model.snapshot)
        }
        .sheet(isPresented: $showingKnowledge) {
            BatteryKnowledgeView()
        }
        .onAppear {
            NSApp.setActivationPolicy(.regular)
        }
        .onDisappear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let appDelegate = NSApp.delegate as? BatteryLoggerAppDelegate {
                    appDelegate.updateDockStatus()
                }
            }
        }
    }

    // MARK: - Header & Footer

    @ViewBuilder
    private var dashboardHeaderView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Mac 電池耗電記錄器").font(.title2.bold())
                    Text("v2.0.0")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12), in: Capsule())

                    if UpdateChecker.shared.hasUpdate, let newVer = UpdateChecker.shared.latestVersion {
                        Button {
                            if let url = UpdateChecker.shared.releaseURL {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.circle.fill")
                                Text("有新版 \(newVer)")
                            }
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.orange)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.16), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("發現新版本，點擊前往 GitHub 下載更新")
                    }
                }
                HStack(spacing: 6) {
                    Text("即時電化學監測 ＋ 智慧保養").font(.caption).foregroundStyle(Color.secondary)
                    Text("•").foregroundStyle(Color.secondary.opacity(0.4))
                    Text("開發者：Matt").font(.caption.bold()).foregroundStyle(Color.primary)
                }
            }
            Spacer()
            Button {
                BatteryLoggerAppDelegate.showPreferencesWindow(model: model)
            } label: {
                Label("設定", systemImage: "gearshape")
            }
            .controlSize(.small)

            Button {
                model.exportDiagnosticReport()
            } label: {
                Label("匯出", systemImage: "square.and.arrow.up")
            }
            .controlSize(.small)

            Button {
                BatteryLoggerAppDelegate.toggleBuddyWindow(model: model)
            } label: {
                Label("✦ 精靈", systemImage: "sparkles")
            }
            .controlSize(.small)

            Button {
                showingKnowledge = true
            } label: {
                Label("指南", systemImage: "book.closed")
            }
            .controlSize(.small)

            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .controlSize(.small)
            .help("立即重新讀取所有硬體與電池數值")
        }
    }

    @ViewBuilder
    private var footerView: some View {
        Text("更新時間：\(model.snapshot.updated.formatted(date: .omitted, time: .standard)) · 資料位於 Library/Application Support/Battery Logger")
            .font(.caption2).foregroundStyle(Color.secondary.opacity(0.7))
    }

    // MARK: - Tab 1: ⚡️ 能源概覽

    @ViewBuilder
    private var overviewTab: some View {
        heroBatteryCard

        HStack(spacing: 12) {
            metric(model.snapshot.charging == true ? "電池端充電功率" : "即時放電功率",
                   model.snapshot.charging == true
                    ? (model.snapshot.chargeWatts.map { String(format: "%.2f W", $0) } ?? "充電中，電流暫低")
                    : (model.snapshot.dischargeWatts.map { String(format: "%.2f W", $0) } ?? "目前未放電"),
                   icon: model.snapshot.charging == true ? "bolt.fill" : "arrow.down")
            metric("記錄狀態", model.recording ? "記錄中 · 每 10 秒" : "未記錄", icon: "waveform.path.ecg")
            metric("CPU 溫度", model.snapshot.cpuTemperature.map { String(format: "%.1f °C", $0) } ?? "此機型未提供", icon: "thermometer.medium")
        }

        ChargeLimiterCard(model: model)
        BatteryImpactCard(analysis: model.snapshot.impactAnalysis)

        LazyVGrid(columns: columns, spacing: 12) {
            InfoCard(title: "系統硬體規格", icon: "desktopcomputer", rows: [
                ("型號", model.snapshot.model), ("處理器", model.snapshot.processor),
                ("記憶體", model.snapshot.memory), ("macOS", "\(model.snapshot.macOS) (\(model.snapshot.build))"),
                ("App 版本", "v2.0.0 (Build 50) · 開發者：Matt"),
                ("本次開機", model.snapshot.uptime)
            ])
            InfoCard(
                title: "電芯與健康即時狀態",
                icon: model.snapshot.batterySymbol,
                iconColor: model.snapshot.batteryIconColor,
                rows: [
                    ("目前電量", model.snapshot.percent.map { "\($0)%" } ?? "—"),
                    ("健康度 (SOH)", model.snapshot.healthPercent.map { String(format: "%.1f%% (%@/%@ mAh)", $0, model.snapshot.fullCapacity.map(String.init) ?? "—", model.snapshot.designCapacity.map(String.init) ?? "—") } ?? "—"),
                    ("循環與階段", {
                        if let cycles = model.snapshot.cycles {
                            if cycles < 300 { return "\(cycles) 次（青年期）" }
                            else if cycles < 600 { return "\(cycles) 次（穩健中年期）" }
                            else if cycles < 800 { return "\(cycles) 次（成熟後期）" }
                            else { return "\(cycles) 次（高循環期）" }
                        }
                        return "—"
                    }()),
                    ("電芯平衡", model.snapshot.cellBalanceText),
                    ("電壓／電流", "\(model.snapshot.voltage.map(String.init) ?? "—") mV / \(model.snapshot.current.map(String.init) ?? "—") mA"),
                    ("電源狀態", model.snapshot.powerStatusText),
                    ("溫度／功率", "\(model.snapshot.temperature.map { String(format: "%.1f °C", $0) } ?? "—") / \(model.snapshot.batteryPowerWatts.map { String(format: "%+.2f W", $0) } ?? "—")")
                ],
                actionTitle: "深度體檢"
            ) { showingBatteryDetails = true }
        }
    }

    @ViewBuilder
    private var heroBatteryCard: some View {
        GroupBox {
            HStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(model.snapshot.batteryIconColor.opacity(0.12))
                        .frame(width: 74, height: 74)

                    Image(systemName: model.snapshot.batterySymbol)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(model.snapshot.batteryIconColor)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(model.snapshot.percent ?? 0)%")
                            .font(.system(size: 38, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.primary)

                        HStack(spacing: 4) {
                            Image(systemName: model.chargerSpeedRating.icon)
                            Text(model.chargerSpeedRating.text)
                        }
                        .font(.caption.bold())
                        .foregroundStyle(model.chargerSpeedRating.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(model.chargerSpeedRating.color.opacity(0.12), in: Capsule())
                    }

                    HStack(spacing: 10) {
                        HStack(spacing: 3) {
                            Text("SOH：").font(.caption).foregroundStyle(Color.secondary)
                            Text(model.snapshot.healthPercent.map { String(format: "%.1f%%", $0) } ?? "—")
                                .font(.caption.bold()).foregroundStyle(Color.green)
                        }
                        .help("目前滿充電容量相對於原廠設計容量的健康百分比")

                        Text("•").foregroundStyle(Color.secondary.opacity(0.4))

                        HStack(spacing: 3) {
                            Text("循環：").font(.caption).foregroundStyle(Color.secondary)
                            Text("\(model.snapshot.cycles ?? 0) 次")
                                .font(.caption.bold())
                        }
                        .help("每累積耗損滿 100% 總電量算 1 次循環")

                        Text("•").foregroundStyle(Color.secondary.opacity(0.4))

                        HStack(spacing: 3) {
                            Text("溫度：").font(.caption).foregroundStyle(Color.secondary)
                            Text(model.snapshot.temperature.map { String(format: "%.1f°C", $0) } ?? "—")
                                .font(.caption.bold())
                        }
                        .help("電池內部即時溫度，超過 36°C 建議移至通風處")

                        Text("•").foregroundStyle(Color.secondary.opacity(0.4))

                        HStack(spacing: 3) {
                            Text("壓差：").font(.caption).foregroundStyle(Color.secondary)
                            Text(model.snapshot.cellBalanceText)
                                .font(.caption.bold()).foregroundStyle(Color.blue)
                        }
                        .help("3 串鋰電芯之間的微伏壓差，小於 15mV 為極佳平衡狀態")
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("硬體充電限制")
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)

                    Text("\(model.displayChargeLimit)%")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(model.displayChargeLimit < 100 ? Color.green : Color.secondary)

                    if let badge = model.displayChargeLimitBadge {
                        Text(badge)
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(model.isSailingPaused ? Color.cyan : (model.isDischargeOnACActive ? Color.purple : Color.green))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((model.isSailingPaused ? Color.cyan : (model.isDischargeOnACActive ? Color.purple : Color.green)).opacity(0.12), in: Capsule())
                    }
                }
                .padding(.trailing, 6)
            }
            .padding(10)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("目前電量 \(model.snapshot.percent ?? 0)%，健康度 \(model.snapshot.healthPercent.map { String(format: "%.1f%%", $0) } ?? "未知")，循環次數 \(model.snapshot.cycles ?? 0) 次")
    }

    // MARK: - Tab 2: 🧠 智能守護與 AI

    @ViewBuilder
    private var intelligenceTab: some View {
        SmartIntelligenceCard(model: model)
    }

    // MARK: - Tab 3: 🔬 深度技術與分析

    @ViewBuilder
    private var diagnosticsTab: some View {
        cellSwellCard
        calibrationCard

        if !model.healthHistory.isEmpty {
            healthHistoryCard
        }

        loggingControlCard
        comparisonCard
        activityMonitorCard
    }

    @ViewBuilder
    private var cellSwellCard: some View {
        GroupBox {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill((model.snapshot.cellSwellRisk?.level.color ?? .green).opacity(0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.title2)
                        .foregroundStyle(model.snapshot.cellSwellRisk?.level.color ?? .green)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("電芯微膨脹與壓差早期預警")
                            .font(.subheadline.bold())
                        if let swell = model.snapshot.cellSwellRisk {
                            Text(swell.level.title)
                                .font(.caption2.bold())
                                .foregroundStyle(swell.level.color)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(swell.level.color.opacity(0.12), in: Capsule())
                        }
                    }

                    if let swell = model.snapshot.cellSwellRisk {
                        Text(swell.tip)
                            .font(.caption2)
                            .foregroundStyle(Color.secondary)
                    }

                    HStack(spacing: 12) {
                        Text("電芯即時電壓：\(model.snapshot.cellVoltages.isEmpty ? "未公開" : model.snapshot.cellVoltages.map { "\($0) mV" }.joined(separator: " · "))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                        if let delta = model.snapshot.cellImbalanceMv {
                            Text("最大壓差：\(delta) mV")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(delta > 35 ? Color.orange : Color.green)
                        }
                    }
                    .padding(.top, 2)
                }
                Spacer()
            }
            .padding(6)
        } label: {
            Label("電芯微觀健康度 · 物理鼓包防範", systemImage: "waveform.path.badge.plus")
                .font(.headline)
        }
    }

    @ViewBuilder
    private var calibrationCard: some View {
        GroupBox {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: "gauge.with.needle")
                        .font(.title2)
                        .foregroundStyle(Color.orange)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("庫侖計電量計校準助理")
                            .font(.subheadline.bold())
                        Spacer()
                        if model.isCalibrating {
                            Text("校準進行中（步驟 \(model.calibrationStep)/2）")
                                .font(.caption2.bold())
                                .foregroundStyle(Color.purple)
                        } else if let last = model.lastCalibrationDate {
                            let days = max(0, Int(Date().timeIntervalSince(last) / 86400))
                            Text("距上次校準已 \(days) 天")
                                .font(.caption2)
                                .foregroundStyle(days > 45 ? Color.orange : Color.secondary)
                        } else {
                            Text("建議每 45-60 天校準一次")
                                .font(.caption2)
                                .foregroundStyle(Color.secondary)
                        }
                    }

                    Text("長期將電量鎖在 80% 時，Mac 庫侖計可能累積微量容量估計誤差。校準引導透過單次完整放電（15%）與慢充（100%）重置晶片電化學基準線。")
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)

                    if model.isCalibrating {
                        HStack {
                            Text(model.calibrationStep == 1 ? "請正常使用並拔除電源，放電至 15% 以下…" : "請連接充電器慢充至 100%，並持續插電 2 小時…")
                                .font(.caption.bold())
                                .foregroundStyle(Color.purple)
                            Spacer()
                            Button(model.calibrationStep == 1 ? "已低於 15%（進入下一步）" : "已充飽 100%（完成校準）") {
                                model.advanceCalibrationStep()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                            .controlSize(.small)
                        }
                        .padding(.top, 2)
                    } else {
                        HStack {
                            Button("開始引導校準流程") {
                                model.startCalibration()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            Spacer()
                        }
                        .padding(.top, 2)
                    }
                }
            }
            .padding(6)
        } label: {
            Label("電量精度校準 · 消除虛電與跳電", systemImage: "arrow.triangle.2.circlepath.circle")
                .font(.headline)
        }
    }

    @ViewBuilder
    private var healthHistoryCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("電池長期健康度與容量歷史記錄", systemImage: "chart.xyaxis.line")
                        .font(.headline)
                    Spacer()
                    Text("已累計記錄 \(model.healthHistory.count) 天樣本")
                        .font(.caption).foregroundStyle(Color.secondary)
                }
                HStack(spacing: 24) {
                    if let first = model.healthHistory.first, let last = model.healthHistory.last {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("首日紀錄健康度").font(.caption).foregroundStyle(Color.secondary)
                            Text(String(format: "%.1f%% (%@)", first.health, first.date))
                                .font(.subheadline.bold())
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("當前健康度").font(.caption).foregroundStyle(Color.secondary)
                            Text(String(format: "%.1f%% (%@)", last.health, last.date))
                                .font(.subheadline.bold())
                                .foregroundStyle(Color.green)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("循環累積歷程").font(.caption).foregroundStyle(Color.secondary)
                            Text("\(last.cycles) 次 (累積增加 +\(max(0, last.cycles - first.cycles)) 次)")
                                .font(.subheadline.bold())
                        }
                        Spacer()
                        Button("匯出完整診斷報告") {
                            model.exportDiagnosticReport()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .padding(6)
        }
    }

    @ViewBuilder
    private var loggingControlCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button(model.recording ? "停止記錄" : "開始記錄") {
                        model.recording ? model.stopRecording() : model.startRecording()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(model.recording ? Color.red : Color.accentColor)

                    if model.recording {
                        Text("CSV：\(model.logPath)").font(.caption).lineLimit(1).textSelection(.enabled)
                    }

                    Button("開啟記錄資料夾") { model.openLogFolder() }
                    Spacer()
                }

                Text("百分比採用電池控制器的 UISoc；電池端瓦數由電流 × 電壓即時計算，代表流入／流出電池之淨功率。")
                    .font(.caption2).foregroundStyle(Color.secondary)
            }
            .padding(4)
        } label: {
            Label("電池取樣與 CSV 記錄", systemImage: "waveform.path.ecg")
                .font(.headline)
        }
    }

    @ViewBuilder
    private var comparisonCard: some View {
        GroupBox("比較兩次測試記錄") {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Button(model.comparisonFileA.isEmpty ? "選記錄 A…" : "更換記錄 A…") { model.chooseComparisonFile(0) }
                    Button(model.comparisonFileB.isEmpty ? "選記錄 B…" : "更換記錄 B…") { model.chooseComparisonFile(1) }
                    if !model.comparisonFileA.isEmpty && !model.comparisonFileB.isEmpty {
                        Button("重新比較") { model.compareSessions() }
                    }
                }
                if !model.comparisonFileA.isEmpty || !model.comparisonFileB.isEmpty {
                    Text("A：\(model.comparisonFileA.isEmpty ? "尚未選取" : URL(fileURLWithPath: model.comparisonFileA).lastPathComponent)　B：\(model.comparisonFileB.isEmpty ? "尚未選取" : URL(fileURLWithPath: model.comparisonFileB).lastPathComponent)")
                        .font(.caption).foregroundStyle(Color.secondary).lineLimit(1)
                }
                if let report = model.compareResult {
                    ScrollView {
                        Text(report).font(.callout).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 145)
                } else {
                    Text("選取兩個 CSV 記錄，自動比較系統版本、測試時長、電量與容量變化、清醒期間 Wh，以及記錄到的合蓋睡眠時間。")
                        .font(.caption).foregroundStyle(Color.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var activityMonitorCard: some View {
        GroupBox("其他 App 的耗電監控與分析") {
            VStack(alignment: .leading, spacing: 8) {
                Text("活動監視器的「能源」頁面會顯示程序的 Energy Impact 指標；powermetrics 也能在命令列列出各行程功耗。")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)

                HStack {
                    Button("打開活動監視器") { model.openActivityMonitor() }
                    Button("複製程序耗電指令") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("sudo powermetrics --samplers tasks --show-process-energy -i 10000 -n 6", forType: .string)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private func metric(_ title: String, _ value: String, icon: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if let icon {
                Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            } else {
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Text(value).font(.title3.monospacedDigit().bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14).background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)：\(value)")
    }
}

struct BatteryImpactCard: View {
    let analysis: BatteryImpactAnalysis

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: analysis.level.icon)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(analysis.level.color)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(analysis.title)
                                .font(.headline)
                                .foregroundStyle(analysis.level.color)

                            Spacer()

                            Text(analysis.cellVoltageEstimate)
                                .font(.caption.monospacedDigit())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.primary.opacity(0.08), in: Capsule())
                        }
                        Text(analysis.description)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                }

                Divider()

                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text(analysis.suggestion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
        } label: {
            Label("目前狀態對電池之影響評估", systemImage: "waveform.path.ecg")
                .font(.headline)
        }
    }
}

struct ChargeLimiterCard: View {
    @ObservedObject var model: BatteryModel

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    HStack(spacing: 6) {
                        Text("充電上限保養")
                            .font(.headline)
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                            .help("透過 Apple SMC (BCLM) 硬體控制，直接在晶片層面截斷充電，大幅延緩鋰電池高電壓膨脹與衰退。")

                        Text("目前限制：\(model.displayChargeLimit)%")
                            .font(.caption.bold())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(model.displayChargeLimit < 100 ? Color.green.opacity(0.2) : Color.blue.opacity(0.2), in: Capsule())
                            .foregroundStyle(model.displayChargeLimit < 100 ? Color.green : Color.blue)
                    }
                    Spacer()
                    if model.isSettingLimit {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if model.isAppleSilicon {
                    HStack(spacing: 6) {
                        Image(systemName: "apple.logo")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                        Text("此 Mac 為 Apple Silicon 架構。硬體 SMC BCLM 限充為 Intel 專屬；在 Apple Silicon 上建議搭配 macOS「最佳化電池充電」進行日常保養。")
                            .font(.caption2)
                            .foregroundStyle(Color.secondary)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }

                HStack(spacing: 12) {
                    Button {
                        model.setChargeLimit(85)
                    } label: {
                        VStack(spacing: 3) {
                            HStack(spacing: 4) {
                                if model.displayChargeLimit == 85 && !model.boostModeActive {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.green)
                                }
                                Text("85% 限制")
                                    .font(.subheadline.bold())
                            }
                            Text("日常保養首選")
                                .font(.caption2)
                                .foregroundStyle(Color.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                    }
                    .buttonStyle(.bordered)
                    .tint(model.displayChargeLimit == 85 && !model.boostModeActive ? Color.green : Color.primary)
                    .disabled(model.isSettingLimit)
                    .help("電芯電壓維持在 ~4.05V，氧化衰退率極低，是原廠常駐插電最佳數值")

                    Button {
                        model.setChargeLimit(90)
                    } label: {
                        VStack(spacing: 3) {
                            HStack(spacing: 4) {
                                if model.displayChargeLimit == 90 && !model.boostModeActive {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.blue)
                                }
                                Text("90% 限制")
                                    .font(.subheadline.bold())
                            }
                            Text("兼顧續航平衡")
                                .font(.caption2)
                                .foregroundStyle(Color.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                    }
                    .buttonStyle(.bordered)
                    .tint(model.displayChargeLimit == 90 && !model.boostModeActive ? Color.blue : Color.primary)
                    .disabled(model.isSettingLimit)
                    .help("電芯約 4.10V，比 100% 顯著健康，又多爭取 5% 出門電量")

                    Button {
                        model.activateBoostMode()
                    } label: {
                        VStack(spacing: 3) {
                            HStack(spacing: 4) {
                                if model.boostModeActive || (model.displayChargeLimit == 100 && !model.isSettingLimit) {
                                    Image(systemName: "bolt.badge.clock.fill")
                                        .foregroundStyle(Color.orange)
                                }
                                Text("100% 外出")
                                    .font(.subheadline.bold())
                            }
                            Text("外出衝刺滿電")
                                .font(.caption2)
                                .foregroundStyle(Color.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                    }
                    .buttonStyle(.bordered)
                    .tint(model.displayChargeLimit == 100 || model.boostModeActive ? Color.orange : Color.primary)
                    .disabled(model.isSettingLimit)
                    .help("本次充至 100%，拔除電源外出後，下次接電自動回歸 85% 保養")
                }

                if model.snapshot.externalPower == true, let pct = model.snapshot.percent, pct > model.userTargetLimit {
                    HStack {
                        Button {
                            model.toggleDischargeOnAC()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: model.isDischargeOnACActive ? "arrow.down.circle.fill" : "arrow.down.circle")
                                Text(model.isDischargeOnACActive ? "正在主動放電降至 \(model.userTargetLimit)% (點擊取消)" : "降電至上限：由電池主動放電至 \(model.userTargetLimit)%")
                                    .font(.caption.bold())
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(model.isDischargeOnACActive ? Color.purple : Color.blue)
                        .controlSize(.small)
                        .help("插著充電線時主動切換至純電池放電，降至 \(model.userTargetLimit)% 後自動切回外接電源旁路保護。")
                    }
                    .padding(.top, 2)
                }

                HStack {
                    Toggle(isOn: $model.smartAutoPilot) {
                        HStack(spacing: 5) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(Color.purple)
                            Text("智慧調節 (Auto-Pilot)")
                                .font(.caption.bold())
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("自動防護：溫度 > 36.5°C 自動降至 85% 防膨脹；拔掉充電線自動退出 100% 恢復 85% 保養")

                    Spacer()

                    Toggle(isOn: $model.sailingModeEnabled) {
                        HStack(spacing: 4) {
                            Image(systemName: "sailboat.fill")
                                .foregroundStyle(Color.cyan)
                            Text("航行保護 (Sailing)")
                                .font(.caption.bold())
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("達上限後切斷充電，允許電量自然滑行釋放壓力（80% -> 75%），徹底消滅 79%~80% 頻繁微充循環！")

                    if NSScreen.screens.count > 1 && model.dockModeEnabled {
                        HStack(spacing: 3) {
                            Image(systemName: "display.2")
                            Text("底座模式 75%")
                        }
                        .font(.caption2.bold())
                        .foregroundStyle(Color.indigo)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.indigo.opacity(0.12), in: Capsule())
                        .help("偵測到外接顯示器，自動以 75% 甜蜜點供電，保護電池免受螢幕反向 PD 高熱影響。")
                    }
                }
                .padding(.top, 2)

                if let msg = model.limitMessage {
                    Text(msg)
                        .font(.caption2)
                        .foregroundStyle(msg.contains("失敗") ? Color.red : Color.green)
                }
            }
            .padding(10)
        } label: {
            Label("電池保養 · 充電上限控制", systemImage: "shield.lefthalf.filled")
                .font(.headline)
        }
    }
}

struct SmartIntelligenceCard: View {
    @ObservedObject var model: BatteryModel

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Text("結合即時感測、充電協議握手分析、行程自動化與化學衰退精算，全方位守護 Mac 能源與電池壽命。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                geminiDiagnosisSection
                chargerAndLongevityGrid
                vampireSection
                sleepAndCalendarGrid
            }
            .padding(12)
        } label: {
            Label("⚡️ 智能體質與自動化守護診斷", systemImage: "wand.and.stars")
                .font(.headline)
        }
    }

    @ViewBuilder
    private var geminiDiagnosisSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.purple)
                    Text("🧠 Google Gemini AI 電化學即時問診顧問")
                        .font(.subheadline.bold())
                }
                Spacer()
                Button {
                    model.requestGeminiDiagnosticReport()
                } label: {
                    HStack(spacing: 4) {
                        if model.isGeminiQuerying {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "wand.and.stars")
                        }
                        Text("一鍵生成 Gemini 深度健檢報告")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .controlSize(.small)
                .disabled(model.isGeminiQuerying)
            }

            if let resp = model.geminiAiResponse {
                ScrollView {
                    Text(resp)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 180)
                .background(Color.purple.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            } else {
                Text("點擊「一鍵生成 Gemini 深度健檢報告」，AI 將全面讀取當前硬體數值、SOH、循環數與電芯壓差，以專業電化學視角給予完整評估與保養策略。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.purple.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var chargerAndLongevityGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            // 1. 🔌 充電器與線材體質健檢
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "cable.connector")
                        .foregroundStyle(.blue)
                    Text("充電器與線材體質健檢")
                        .font(.subheadline.bold())
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(model.snapshot.chargerRatingText)
                            .font(.caption.bold())
                            .foregroundStyle(.primary)
                        Spacer()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(model.snapshot.magSafeLedState.color)
                                .frame(width: 6.5, height: 6.5)
                            Text(model.snapshot.magSafeLedState.title)
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(model.snapshot.magSafeLedState.color)
                        }
                    }

                    if model.isLowPowerModeActive {
                        HStack(spacing: 3) {
                            Image(systemName: "leaf.fill")
                            Text("macOS 低耗電模式生效中")
                        }
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(Color.green)
                        .padding(.vertical, 1)
                    }

                    if let desc = model.snapshot.adapterDescription {
                        Text(desc)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if model.snapshot.externalPower == true, let timeRemaining = model.snapshot.timeToReachLimit(limit: model.displayChargeLimit) {
                        Text("充至 \(model.displayChargeLimit)% 預計：\(timeRemaining.text)")
                            .font(.caption2.bold())
                            .foregroundStyle(.green)
                    }

                    if let cable = model.snapshot.cableHealthAnalysis {
                        Divider().padding(.vertical, 2)
                        HStack(spacing: 4) {
                            Text("線材品質：").font(.caption2).foregroundStyle(.secondary)
                            Text(cable.grade.title)
                                .font(.caption2.bold())
                                .foregroundStyle(cable.grade.color)
                        }
                        Text("輸入 \(String(format: "%.1fW", cable.inputWatts)) · 損耗 \(String(format: "%.1f%%", cable.lossPercent)) · \(cable.advice)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }

            // 2. ⏳ 電池化學壽命推估與殘值精算
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "hourglass.badge.plus")
                        .foregroundStyle(.purple)
                    Text("壽命推估與二手轉售殘值")
                        .font(.subheadline.bold())
                }
                VStack(alignment: .leading, spacing: 3) {
                    if let years = model.snapshot.estimatedRemainingYears {
                        Text("推估優質服役壽命：約 \(String(format: "%.1f", years)) 年")
                            .font(.caption.bold())
                            .foregroundStyle(.purple)
                    } else {
                        Text("推估優質服役壽命：計算中")
                            .font(.caption.bold())
                    }
                    Text("轉售殘值保護：\(model.snapshot.resaleValuePreservationText)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.purple.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    @ViewBuilder
    private var vampireSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "ladybug.fill")
                    .foregroundStyle(model.isRogueDrainAlert ? .red : .orange)
                Text("偷電怪獸抓賊偵探（背景耗電進程監控）")
                    .font(.subheadline.bold())
                Spacer()
                if model.snapshot.externalPower == false {
                    Text("電池放電中：\(String(format: "%.1f", model.snapshot.dischargeWatts ?? 0)) W")
                        .font(.caption2.bold())
                        .foregroundStyle(model.isRogueDrainAlert ? Color.red : Color.secondary)
                } else {
                    Text("外接供電中（暫無電池放電耗損）")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if !model.topEnergyVampires.isEmpty {
                VStack(spacing: 4) {
                    ForEach(model.topEnergyVampires.prefix(3)) { app in
                        HStack {
                            Text(app.name)
                                .font(.caption.bold())
                            Spacer()
                            Text("\(String(format: "%.1f", app.cpuPercent))% CPU")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(app.cpuPercent >= 20.0 ? Color.red : Color.secondary)

                            Button("關閉") {
                                model.terminateVampireApp(pid: app.id)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            } else {
                HStack {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                    Text("系統背景清爽，未偵測到失控高耗能偷電應用程式。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var sleepAndCalendarGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            // Sleep Guardian
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "moon.zzz.fill")
                        .foregroundStyle(.indigo)
                    Text("背包防悶燒與睡眠守護")
                        .font(.subheadline.bold())
                }
                VStack(alignment: .leading, spacing: 3) {
                    if let sleep = model.lastSleepReport {
                        Text("最近休眠（\(String(format: "%.1f", sleep.durationHours)) 小時）：掉電 \(sleep.drainPercent)%")
                            .font(.caption.bold())
                        Text("喚醒溫度：\(String(format: "%.1f°C", sleep.wakeTemperature)) · \(sleep.summary)")
                            .font(.caption2)
                            .foregroundStyle(sleep.isSafe ? Color.secondary : Color.red)
                    } else {
                        Text("暫無最近休眠取樣。闔蓋睡眠時系統將自動記錄耗電與溫度變化，防止在電腦包內悶燒。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.indigo.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }

            // Calendar & Departure Schedule
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(.teal)
                    Text("外出預測與出門定時衝刺")
                        .font(.subheadline.bold())
                }
                VStack(alignment: .leading, spacing: 3) {
                    if let outing = model.calendarOutingAlert {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("行程：\(outing.title)")
                                    .font(.caption.bold())
                                Text("時間：\(outing.timeDescription)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("衝刺 100%") {
                                model.activateBoostMode()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.teal)
                            .controlSize(.mini)
                        }
                    } else if model.departureScheduleEnabled {
                        HStack {
                            Text("已預約出門：\(model.departureTimeString)")
                                .font(.caption.bold())
                                .foregroundStyle(Color.teal)
                            Spacer()
                            Text("出發前 1h 自動衝刺")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("未來 4 小時無行程。維持 85% 最佳保養上限（可在設定開啟每日定時衝刺）。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

struct InfoCard: View {
    let title: String
    let icon: String
    var iconColor: Color? = nil
    let rows: [(String, String)]
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(rows.indices, id: \.self) { i in
                    HStack(alignment: .firstTextBaseline) {
                        Text(rows[i].0).foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
                        Text(rows[i].1).textSelection(.enabled).lineLimit(2)
                        Spacer(minLength: 0)
                    }.font(.callout)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
        } label: {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .foregroundStyle(iconColor ?? .primary)
                    Text(title)
                }
                .font(.headline)

                Spacer()
                if let actionTitle, let action {
                    Button(actionTitle, action: action).font(.caption)
                }
            }
        }
    }
}

struct BatteryDetailsView: View {
    let snapshot: BatterySnapshot
    @Environment(\.dismiss) private var dismiss
    private var compatibility: BatteryCompatibility? { BatteryCompatibility.catalog[snapshot.model] }

    private var rows: [(String, String)] {
        let list: [(String, String)] = [
            ("Mac 型號識別碼", snapshot.model),
            ("電池序號 (Serial)", snapshot.serialNumber),
            ("電池製造商標記", snapshot.manufacturer),
            ("控制器型號", snapshot.controllerModel),
            ("電池狀態", snapshot.powerStatusText),
            ("目前電量", snapshot.percent.map { "\($0)%（UISoc 系統顯示值）" } ?? "—"),
            ("目前／滿充容量", "\(snapshot.capacity.map(String.init) ?? "—") / \(snapshot.fullCapacity.map(String.init) ?? "—") mAh"),
            ("設計容量", snapshot.designCapacity.map { "\($0) mAh" } ?? "系統未提供"),
            ("真實化學健康度 (SOH)", snapshot.healthPercent.map { String(format: "%.1f%%（滿充容量 ÷ 設計容量）", $0) } ?? "系統未提供"),
            ("循環次數階段", snapshot.cycleStageExplanation),
            ("電壓／電流", "\(snapshot.voltage.map(String.init) ?? "—") mV / \(snapshot.current.map(String.init) ?? "—") mA"),
            ("各電芯獨立電壓", snapshot.cellVoltages.isEmpty ? "未提供" : snapshot.cellVoltages.enumerated().map { "芯\($0 + 1): \(Double($1) / 1000)V" }.joined(separator: "  |  ")),
            ("電芯壓差一致性", snapshot.cellBalanceText),
            ("各芯化學容量 (Qmax)", snapshot.qmax.isEmpty ? "未提供" : snapshot.qmax.enumerated().map { "芯\($0 + 1): \($1) mAh" }.joined(separator: "  |  ")),
            ("電池端功率", snapshot.batteryPowerWatts.map { String(format: "%+.2f W", $0) } ?? "—"),
            ("電池溫度", snapshot.temperature.map { String(format: "%.1f °C", $0) } ?? "—"),
            ("健康狀態", snapshot.condition),
            ("硬體故障保護標記", snapshot.permanentFailureStatus == 0 ? "正常 (PF=0，無硬體熔斷鎖死)" : "異常 (PF=\(snapshot.permanentFailureStatus ?? -1))"),
            ("充電器連線", snapshot.externalPower.map { $0 ? "已連接" : "未連接" } ?? "—"),
            ("外部充電支援", snapshot.externalChargeCapable.map { $0 ? "支援" : "不支援" } ?? "系統未提供"),
            ("估計剩餘時間", snapshot.timeRemaining.flatMap { $0 > 0 && $0 < 65535 ? $0 : nil }.map { "\($0 / 60) 小時 \($0 % 60) 分" } ?? "目前無估值"),
            ("電量計誤差指標 (MaxErr)", snapshot.maxError.map { "\($0)%（< 3% 代表計量高度精確）" } ?? "系統未提供")
        ]
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("電池詳細資訊").font(.title2.bold())
                    Text("來源：macOS AppleSmartBattery 電池控制器資料").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }
            }
            Text("Mac 型號識別碼可用來核對相容電池；它不是電池料號。macOS 未提供獨立的電池包型號時，會顯示「系統未提供」。控制器型號是電池管理晶片識別，不一定是電池包商品型號。估算健康度以滿充容量除以設計容量計算，會受電量計校正影響。")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Text("購買電池前，請用上方 Mac 型號識別碼比對供應商的相容清單；若商品要求 A 開頭機型號碼，請另外核對機身標示或「關於本機」。")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("複製識別碼") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(snapshot.model, forType: .string)
                }
                .disabled(snapshot.model == "—" || snapshot.model == "讀取中…")
            }
            GroupBox("依機型識別碼查到的替換電池") {
                VStack(alignment: .leading, spacing: 8) {
                    if let compatibility {
                        detailRow("Mac 機身型號", compatibility.machineModel)
                        detailRow("替換電池型號", compatibility.batteryModel)
                        detailRow("標示規格", compatibility.capacity)
                        Text("這是零件供應商的替換電池型號，不是 Apple 維修料號；購買前仍要核對完整機型與相容清單。")
                            .font(.caption).foregroundStyle(.secondary)
                        if let url = URL(string: compatibility.sourceURL) {
                            Link(compatibility.sourceTitle, destination: url)
                                .font(.caption)
                        }
                    } else {
                        Text("資料庫尚未收錄此 Mac 型號（\(snapshot.model)），因此不猜測電池料號。請先用型號識別碼向維修商或零件供應商核對。")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            GroupBox("何時建議更換") {
                Label(snapshot.replacementAdvice, systemImage: snapshot.replacementAdviceIcon)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(rows.indices, id: \.self) { index in
                        HStack(alignment: .firstTextBaseline) {
                            Text(rows[index].0).foregroundStyle(.secondary)
                            Spacer(minLength: 16)
                            Text(rows[index].1).multilineTextAlignment(.trailing).textSelection(.enabled)
                        }
                        .font(.callout).padding(.vertical, 10)
                        if index != rows.indices.last { Divider() }
                    }
                }
            }
        }
        .padding(22)
        .frame(minWidth: 500, minHeight: 560)
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .font(.callout)
    }
}

struct BatteryKnowledgeView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("鋰電池保養科學與老化指南", systemImage: "book.closed.fill")
                    .font(.title2.bold())
                Spacer()
                Button("關閉") { dismiss() }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    GroupBox("⚡ 鋰電池加速老化的四大元兇（權威電化學原理）") {
                        VStack(alignment: .leading, spacing: 12) {
                            topicItem(
                                title: "1. 致命第一名：高溫 ＋ 100% 極限滿電長久待機",
                                subtitle: "化學原理：日曆老化（Calendar Aging）與電解液氧化",
                                content: "充到 100% 時電芯承受 4.25V~4.35V 高電壓，正極處於極度氧化態。若筆電伴隨 35°C 以上工作溫度，電解液副反應呈指數級飆升，極易使 SEI 膜暴增、產氣膨脹鼓包。\n• 文獻實測：在 40°C 下維持 100% 電量 1 年，容量損失高達 35%；若在 25°C 下限制在 80%~85%，1 年容量衰退小於 4%。"
                            )

                            Divider()

                            topicItem(
                                title: "2. 深度過放：經常用到 0%～10% 才充電",
                                subtitle: "化學原理：負極集流體（銅箔）溶解與銅枝晶短路",
                                content: "電量低於 20% 時電壓跌破 3.7V 低壓陡坡。若常態性放電到 0%（100% 放電深度 DoD），循環壽命僅約 300~500 次；若日常維持在 20%~85% 之間（60% DoD），等效循環次數可躍升至 1,500~2,500 次以上！"
                            )

                            Divider()

                            topicItem(
                                title: "3. 邊跑重負載發燙邊高速充電",
                                subtitle: "化學原理：鋰金屬析出（Lithium Plating / 死鋰）",
                                content: "大電流充電時若機身過熱，鋰離子來不及嵌入石墨負極層狀結構，容易在負極表面堆積直接還原為金屬死鋰，造成永久不可逆的容量縮減。"
                            )

                            Divider()

                            topicItem(
                                title: "4. 長期不完整校正引起的電量計失真",
                                subtitle: "晶片原理：開路電壓與滿充容量學習漂移（Gauge Drift）",
                                content: "電量計晶片（如德州儀器 bq20z451）需要定期讀取平穩電壓。每隔 2~3 個月正常充放一次，能確保系統顯示的 UISoc 百分比與 MaxErr 保持在 1% 的極高精確度。"
                            )
                        }
                        .padding(.vertical, 6)
                    }

                    GroupBox("💡 普通使用者的黃金保養法則") {
                        VStack(alignment: .leading, spacing: 10) {
                            bullet(title: "長時間外接螢幕／固定插電：", text: "強烈建議啟用「85% 限制」或「90% 限制」。硬體直接切斷充電電流，讓電池脫離極限高壓氧化區。")
                            bullet(title: "外出長途出差：", text: "出發前點擊「100% 解鎖」充飽外出，回辦公室再恢復 85%/90% 限制。")
                            bullet(title: "日常放電使用：", text: "盡量在電量降至 20% 左右時就接上充電器，避免深度過放。")
                            bullet(title: "長期閒置不用（存放數週以上）：", text: "將電量充放至 50% 左右關機存放，處於鋰離子化學結構最穩定的休眠電壓。")
                        }
                        .padding(.vertical, 6)
                    }

                    GroupBox("📚 參考資料與文獻出處") {
                        VStack(alignment: .leading, spacing: 8) {
                            Link("• Battery University (Cadex): BU-808 How to Prolong Lithium-based Batteries",
                                 destination: URL(string: "https://batteryuniversity.com/article/bu-808-how-to-prolong-lithium-based-batteries")!)
                            Link("• Jeff Dahn Research Group (Dalhousie University): A Wide Range Exploration of Aging in Li-ion Cells",
                                 destination: URL(string: "https://iopscience.iop.org/journal/0013-4651")!)
                            Link("• Apple 官方支援：關於 Mac 筆記型電腦中的電池健康度管理",
                                 destination: URL(string: "https://support.apple.com/zh-tw/HT212049")!)
                        }
                        .font(.caption)
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding(22)
        .frame(minWidth: 580, minHeight: 620)
    }

    private func topicItem(title: String, subtitle: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline).foregroundStyle(.primary)
            Text(subtitle).font(.caption.bold()).foregroundStyle(.secondary)
            Text(content).font(.callout).foregroundStyle(.secondary)
        }
    }

    private func bullet(title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•").bold()
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.bold())
                Text(text).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

struct FloatingBuddyView: View {
    @ObservedObject var model: BatteryModel
    @Environment(\.colorScheme) private var colorScheme

    @State private var isBubbleVisible = false
    @State private var isHovering = false
    @State private var isDragging = false
    @State private var dragStartMouse: NSPoint?
    @State private var dragStartOrigin: NSPoint?
    @State private var isChargingPulsing = false
    @State private var reactorPulse = false
    @State private var chargePulse = false
    @State private var unplugBounceScale: CGFloat = 1.0
    @State private var unplugBounceOffset: CGFloat = 0.0

    // Physics & Interactive States
    @State private var pokeFlipDegrees: Double = 0.0
    @State private var isDizzy = false
    @State private var dizzyTimer: Timer?
    @State private var lastDragLocation: NSPoint?
    @State private var lastDragTime = Date()
    @State private var recentVelocities: [CGFloat] = []
    @State private var easterEggText: String?
    @State private var isDocked = false

    private var isCharging: Bool {
        model.snapshot.charging == true || (model.snapshot.externalPower == true && (model.snapshot.current ?? 0) > 50)
    }

    private var moodDetails: (emoji: String, title: String, quote: String, color: Color) {
        if isDizzy {
            return (
                "😵‍💫",
                "哎呀～別甩我呀！",
                "小精靈被快速甩動晃得頭好暈啊！站穩中～請溫柔對待我喔！",
                .pink
            )
        }

        let pct = model.snapshot.percent ?? 50
        let temp = model.snapshot.temperature ?? 25.0
        let isChg = model.snapshot.charging == true
        let limit = model.displayChargeLimit
        let watts = model.snapshot.chargeWatts ?? 0
        let discharge = model.snapshot.dischargeWatts ?? 0
        let hour = Calendar.current.component(.hour, from: Date())

        // 0. Superhero Personas Override (Iron Man & Captain America)
        if model.buddySkin == .arcReactor {
            if isDizzy {
                return ("🦾", "Jarvis: 機體劇烈震盪", "警告：偵測到 Mark 系列裝甲經歷高 G 力翻滾！正在重新校準姿態控制陀螺儀...", .cyan)
            }
            if temp >= 36.0 {
                return ("⚠️", "Jarvis: 核心過熱預警", String(format: "警告：方舟反應爐達到 %.1f°C！推進器冷卻系統已介入，建議減少高能耗運算！", temp), .red)
            }
            if model.isHighDischargeSpike {
                return ("🚨", "Jarvis: 反應爐輸出激增", String(format: "偵測到異常放電：%.1f W！疑似掌心雷射或飛行推進系統全開，請檢視高能耗程序！", discharge), .red)
            }
            if isChg {
                if limit <= 90 && pct >= limit {
                    return ("🦾", "Jarvis: 巡航模式就緒", "方舟核心已鎖定 \(limit)% 巡航保護協議！由外接電源直供裝甲，鈀金核心零損耗。", .cyan)
                } else if watts >= 55.0 {
                    return ("⚡️", "Jarvis: 高壓電弧注入中", String(format: "方舟核心正以 %.0f W 滿載快充%@！能量水平直線飆升中！", watts, model.timeToLimitEstimate.map { "（預計 \($0) 達成）" } ?? ""), .cyan)
                } else {
                    return ("⚡️", "Jarvis: 能量充填中", String(format: "方舟反應爐注入功率 %+.1f W，能量穩定回升中。", watts), .cyan)
                }
            }
            if pct <= 20 && model.snapshot.externalPower == false {
                return ("🪫", "Jarvis: 核心能量匱乏", "『Proof that Tony Stark has a heart.』當前儲備僅剩 \(pct)%，生命維持系統負擔過重，請立即連接外部電源！", .red)
            }
            if model.snapshot.externalPower == true && pct == 100 {
                return ("⚠️", "Jarvis: 核心超載 100%", "方舟反應爐持續處於 4.3V 飽和高壓，Unibeam 充能完畢！建議啟用 85% 巡航限制保護電芯。", .orange)
            }
            return ("🦾", "Jarvis: 系統全綠燈", "方舟反應爐運作完美，3 組磁約束線圈壓差極小，先生，隨時可以升空出動！", .cyan)
        }

        if model.buddySkin == .captainShield {
            if isDizzy {
                return ("🛡️", "隊長：受猛烈撞擊", "防線依然屹立！汎合金護盾正在吸收衝擊動能，我可以跟你耗一整天！", .blue)
            }
            if temp >= 36.0 {
                return ("🔥", "隊長：護盾承受高熱", String(format: "機身溫度 %.1f°C！汎合金護盾正在全力導熱散溫，請將 Mac 移至通風處！", temp), .red)
            }
            if model.isHighDischargeSpike {
                return ("🚨", "隊長：遭遇強力攻擊！", String(format: "放電功率飆至 %.1f W！疑似九頭蛇重火力轟炸，請檢查卡死或高耗能程式！", discharge), .red)
            }
            if isChg {
                if limit <= 90 && pct >= limit {
                    return ("🛡️", "隊長：固若金湯！", "電量已鎖在 \(limit)% 汎合金防護層！旁路供電完全吸收電解液應力，我可以跟你耗一整天！", .blue)
                } else {
                    return ("⚡️", "隊長：雷神之槌充能！", String(format: "接獲外部能源供應（%+.1f W）！護盾動能儲備正在全速回填！", watts), .blue)
                }
            }
            if pct <= 20 && model.snapshot.externalPower == false {
                return ("🥺", "隊長：體力耗盡！", "電量只剩 \(pct)%！盾牌快舉不起來啦，快幫我接上充電樁！", .red)
            }
            if model.snapshot.externalPower == true && pct == 100 {
                return ("😵‍💫", "隊長：能量超載！", "護盾承受著 4.3V 高壓過度充能！建議點擊「85% 限制」維持最佳作戰彈性！", .orange)
            }
            return ("🛡️", "隊長：隨時準備作戰！", "汎合金之盾能量充沛，3 串電芯陣列堅不可摧，復仇者隨時待命！", .blue)
        }

        // 1. Extreme temperature
        if temp >= 36.0 {
            return (
                "🥵",
                "好熱好熱！",
                String(format: "機身溫度 %.1f°C 正在煎熬！本精靈已啟動熱防護，快幫我移到通風涼爽處～", temp),
                .red
            )
        }

        // 2. High discharge power spike (Energy Hog alert)
        if model.isHighDischargeSpike {
            return (
                "🚨",
                "耗電暴增警報！",
                String(format: "放電功率飆高至 %.1f W！可能有背景後台程式正在瘋狂吃電，建議查看活動監視器～", discharge),
                .red
            )
        }

        // 3. Fast charging vs slow charging wattage perception
        if isChg {
            if limit <= 90 && pct >= limit {
                return (
                    "😎",
                    "黃金保養中！",
                    "電量被我精準鎖在 \(limit)% 安全區間！電壓超舒適（~4.05V），電解液完全不氧化～",
                    .green
                )
            } else if watts >= 55.0 {
                let timeTip = model.timeToLimitEstimate.map { "，預計 \($0) 達成保養上限" } ?? ""
                return (
                    "⚡️",
                    "滿血極速快充！",
                    String(format: "以 %.0f W 超大功率狂飆回血中%@，活力滿滿！", watts, timeTip),
                    .green
                )
            } else if watts > 0 && watts < 15.0 {
                return (
                    "💧",
                    "微瓦慢充小水流",
                    String(format: "目前僅以 %.1f W 涓流充能，可能是低功率小充電頭或外接螢幕供電，請多給它一點耐心～", watts),
                    .orange
                )
            } else {
                let timeTip = model.timeToLimitEstimate.map { "（預計 \($0) 達標）" } ?? ""
                return (
                    "⚡",
                    "正在大口充能！",
                    String(format: "以 %+.1f W 穩定回補體力中%@，能量源源不絕～", watts, timeTip),
                    .blue
                )
            }
        }

        // 4. Overcharged at 100% on AC
        if model.snapshot.externalPower == true && pct == 100 {
            return (
                "😵‍💫",
                "吃太撐啦～",
                "電量一直 100% 待機，電芯承受著 4.3V 極限高壓！建議點擊「85% 限制」幫我減壓喔！",
                .orange
            )
        }

        // 5. Low battery hunger
        if pct <= 20 && model.snapshot.externalPower == false {
            return (
                "🥺",
                "肚子快餓扁了…",
                "電量只剩 \(pct)%！負極銅箔正在喊救命，快餵我接上充電器啦！",
                .red
            )
        }

        // 6. Long focus / Pomodoro coffee reminder
        if model.continuousWorkMinutes >= 90 {
            return (
                "☕️",
                "專注好久囉！",
                "主人已經連續工作 \(model.continuousWorkMinutes) 分鐘啦！起來喝口水、望遠 20 秒放鬆雙眼吧～",
                .brown
            )
        }

        // 7. Day & Night Cycle
        if hour >= 23 || hour < 6 {
            return (
                "💤",
                "深夜小憩中…",
                "夜深人靜～小精靈戴上睡帽打瞌睡囉。光暈已自動調暗，主人也別太累早點休息喔！",
                .indigo
            )
        } else if hour >= 6 && hour < 10 {
            return (
                "☀️",
                "早安元氣滿點！",
                "早晨電芯精神飽滿，壓差極度健康！今天也一起高效完成每項工作吧～",
                .orange
            )
        }

        // 8. Normal comfortable discharging
        return (
            "😊",
            "狀態極佳！",
            "目前放電健康順暢，3 串電芯壓差極度平衡，主人請安心專注工作！",
            .purple
        )
    }

    private var windowDragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { _ in
                guard !model.buddyLocked else { return }
                guard let panel = BatteryLoggerAppDelegate.buddyPanel else { return }
                let current = NSEvent.mouseLocation
                let now = Date()

                if dragStartMouse == nil {
                    dragStartMouse = current
                    dragStartOrigin = panel.frame.origin
                    isDragging = true
                    lastDragLocation = current
                    lastDragTime = now
                    recentVelocities.removeAll()
                }

                if let startMouse = dragStartMouse, let startOrigin = dragStartOrigin {
                    let dx = current.x - startMouse.x
                    let dy = current.y - startMouse.y
                    panel.setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))

                    // Physics Shake Detection: track rapid velocity oscillations
                    if let lastLoc = lastDragLocation {
                        let dt = now.timeIntervalSince(lastDragTime)
                        if dt > 0.015 && dt < 0.25 {
                            let vx = (current.x - lastLoc.x) / CGFloat(dt)
                            recentVelocities.append(vx)
                            if recentVelocities.count > 6 { recentVelocities.removeFirst() }

                            var reversals = 0
                            for i in 1..<recentVelocities.count {
                                if (recentVelocities[i] > 400 && recentVelocities[i-1] < -400) ||
                                   (recentVelocities[i] < -400 && recentVelocities[i-1] > 400) {
                                    reversals += 1
                                }
                            }
                            if reversals >= 2 && !isDizzy {
                                isDizzy = true
                                dizzyTimer?.invalidate()
                                dizzyTimer = Timer.scheduledTimer(withTimeInterval: 2.8, repeats: false) { _ in
                                    withAnimation(.spring()) {
                                        self.isDizzy = false
                                    }
                                }
                            }
                        }
                    }
                    lastDragLocation = current
                    lastDragTime = now
                }
            }
            .onEnded { _ in
                guard !model.buddyLocked else { return }
                dragStartMouse = nil
                dragStartOrigin = nil
                lastDragLocation = nil
                recentVelocities.removeAll()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    isDragging = false
                }

                if let panel = BatteryLoggerAppDelegate.buddyPanel {
                    // Smart Edge Docking (Peeking Buddy)
                    if model.edgeDockingEnabled, let screen = panel.screen ?? NSScreen.main {
                        let visible = screen.visibleFrame
                        if panel.frame.minX < visible.minX + 25 {
                            // Dock to left screen edge
                            panel.setFrameOrigin(NSPoint(x: visible.minX - 35, y: panel.frame.minY))
                            isDocked = true
                        } else if panel.frame.maxX > visible.maxX - 25 {
                            // Dock to right screen edge
                            panel.setFrameOrigin(NSPoint(x: visible.maxX - panel.frame.width + 35, y: panel.frame.minY))
                            isDocked = true
                        } else {
                            isDocked = false
                        }
                    }
                    UserDefaults.standard.set(Double(panel.frame.origin.x), forKey: "buddy_pos_x")
                    UserDefaults.standard.set(Double(panel.frame.origin.y), forKey: "buddy_pos_y")
                }
            }
    }

    private func cycleNextSkin() {
        let all = BuddySkin.allCases
        if let idx = all.firstIndex(of: model.buddySkin) {
            let next = all[(idx + 1) % all.count]
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                model.buddySkin = next
            }
        }
    }

    /// Infinite pulse animations are the dominant CPU cost (~30% on Intel); run them only while charging.
    private func updateBuddyPulses(charging: Bool) {
        isChargingPulsing = charging
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            reactorPulse = false
            chargePulse = false
        }
        guard charging else { return }
        DispatchQueue.main.async {
            withAnimation(Animation.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                reactorPulse = true
            }
            withAnimation(Animation.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                chargePulse = true
            }
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isBubbleVisible {
                speechBubbleView
            }
            interactiveAvatarView
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .onAppear {
            updateBuddyPulses(charging: isCharging)
        }
        .onChange(of: isCharging) { newIsCharging in
            updateBuddyPulses(charging: newIsCharging)
            if !newIsCharging {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.45)) {
                    unplugBounceScale = 1.22
                    unplugBounceOffset = -6
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.65)) {
                        unplugBounceScale = 1.0
                        unplugBounceOffset = 0.0
                    }
                }
            }
        }
    }

    // MARK: - Speech Bubble Subviews

    @ViewBuilder
    private var speechBubbleView: some View {
        VStack(alignment: .leading, spacing: 6) {
            bubbleHeaderView
            bubbleQuoteView
            bubbleGeminiChatView
            bubbleIntelligentAlertsView
            bubbleAdviceBoxView
            bubbleFooterView
        }
        .padding(10)
        .frame(width: 268)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    colorScheme == .dark ? Color.white.opacity(0.42) : Color.white.opacity(0.85),
                                    colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.75
                        )
                )
        )
        .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
        .gesture(windowDragGesture)
    }

    @ViewBuilder
    private var bubbleGeminiChatView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let resp = model.geminiAiResponse {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.purple)
                        Text(model.buddySkin == .arcReactor ? "J.A.R.V.I.S. (Gemini)" : "AI 管家 (Gemini)")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.purple)
                        Spacer()
                        Button {
                            withAnimation {
                                model.geminiAiResponse = nil
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8))
                                .foregroundStyle(Color.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Text(resp)
                        .font(.system(size: 9))
                        .foregroundStyle(Color.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(6)
                .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            if model.isGeminiQuerying {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("J.A.R.V.I.S. 正在電化學運算中...")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.secondary)
                }
                .padding(3)
            } else {
                HStack(spacing: 4) {
                    TextField("問問 J.A.R.V.I.S. (Gemini)...", text: $model.geminiAiQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3.5)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                        .onSubmit {
                            model.askGemini()
                        }

                    Button {
                        model.askGemini()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(model.geminiAiQuery.isEmpty ? Color.secondary : Color.purple)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.geminiAiQuery.isEmpty)
                }

                // Quick question chips
                HStack(spacing: 3) {
                    Button("🔋 續航評估") {
                        model.askGemini(customPrompt: "請評估我現在這台 Mac 的電量與放電狀態，還能支撐多久？有何省電技巧？")
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 7.5))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06), in: Capsule())

                    Button("🌡️ 電池健檢") {
                        model.askGemini(customPrompt: "請檢查我這台 Mac 目前的電池溫度、SOH 健康度與循環次數是否健康？")
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 7.5))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06), in: Capsule())

                    Button("💡 今晚充飽？") {
                        model.askGemini(customPrompt: "我今晚筆電插著電，建議維持 85% 還是衝到 100%？請以電化學科學角度簡要分析。")
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 7.5))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                }
            }
        }
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private var bubbleIntelligentAlertsView: some View {
        if model.isRogueDrainAlert, let top = model.topEnergyVampires.first {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("抓到偷電怪獸！")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.red)
                    Spacer()
                    Button("立即終止") {
                        model.terminateVampireApp(pid: top.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.mini)
                }
                Text("「\(top.name)」佔用 \(String(format: "%.0f", top.cpuPercent))% CPU（放電 \(String(format: "%.1f", model.rogueDrainWatts))W）")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .padding(6)
            .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }

        if let outing = model.calendarOutingAlert {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(.blue)
                    Text("行事曆預測外出")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.blue)
                    Spacer()
                    Button("衝刺 100%") {
                        model.activateBoostMode()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .controlSize(.mini)
                }
                Text("\(outing.title)（\(outing.timeDescription)）")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .padding(6)
            .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }

        if model.snapshot.externalPower == true, let timeRemaining = model.snapshot.timeToReachLimit(limit: model.displayChargeLimit) {
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.green)
                Text(model.snapshot.chargerRatingText)
                    .font(.system(size: 8))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Text("至 \(model.displayChargeLimit)%：\(timeRemaining.text)")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    @ViewBuilder
    private var bubbleHeaderView: some View {
        HStack(spacing: 5) {
            Text(moodDetails.title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(moodDetails.color)

            HStack(spacing: 2) {
                Text(model.guardianLevel.stars.prefix(3))
                    .font(.system(size: 8))
                Text("Lv.\(model.guardianLevel.level)")
                    .font(.system(size: 8.5, weight: .bold))
            }
            .foregroundStyle(model.guardianLevel.badgeColor)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(model.guardianLevel.badgeColor.opacity(0.12), in: Capsule())

            Spacer()

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    isBubbleVisible = false
                    BatteryLoggerAppDelegate.updateBuddyPanelSize(isBubbleVisible: false)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .background(Color.primary.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .help("關閉對話泡泡")
        }
    }

    @ViewBuilder
    private var bubbleQuoteView: some View {
        if let egg = easterEggText {
            Text(egg)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.purple)
                .padding(5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        } else {
            Text(moodDetails.quote)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var bubbleAdviceBoxView: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: model.careAdvice.icon)
                    .font(.system(size: 9.5, weight: .bold))
                Text(model.careAdvice.actionTitle)
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(model.careAdvice.badgeColor)

            Text(model.careAdvice.actionTip)
                .font(.system(size: 9.5))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Text(model.careAdvice.cycleScience)
                .font(.system(size: 8.5))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 1)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(model.careAdvice.badgeColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var bubbleFooterView: some View {
        HStack(spacing: 5) {
            Text(model.snapshot.temperature.map { String(format: "🌡️ %.1f°C", $0) } ?? "")
            Text("上限 \(model.displayChargeLimit)%")
                .bold()
                .foregroundStyle(model.displayChargeLimit < 100 ? .green : .secondary)

            if let badge = model.displayChargeLimitBadge {
                Text(badge)
                    .font(.system(size: 8.5, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.blue.opacity(0.12), in: Capsule())
                    .foregroundStyle(.blue)
            }

            Spacer()

            if model.continuousWorkMinutes >= 30 {
                Text("☕️ \(model.continuousWorkMinutes)m")
                    .font(.system(size: 8.5).monospacedDigit())
                    .foregroundStyle(.brown)
            }

            Button {
                cycleNextSkin()
            } label: {
                Image(systemName: "paintpalette.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("切換造型（\(model.buddySkin.displayName)）")

            Button("隱藏") {
                BatteryLoggerAppDelegate.hideBuddyWindow()
            }
            .font(.system(size: 9))
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .font(.system(size: 9.5).monospacedDigit())
        .foregroundStyle(.secondary)
    }

    // MARK: - Interactive Avatar View

    @ViewBuilder
    private var interactiveAvatarView: some View {
        avatarViewForCurrentSkin
            .frame(width: 72, height: 72)
            .scaleEffect(unplugBounceScale)
            .offset(y: unplugBounceOffset)
            .rotationEffect(.degrees(pokeFlipDegrees))
            .scaleEffect(isHovering ? 1.05 : 1.0)
            .contentShape(Circle())
            .gesture(windowDragGesture)
            .onTapGesture(count: 2) {
                guard !isDragging else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
                    pokeFlipDegrees += 360
                }
                let maxV = model.snapshot.cellVoltages.max() ?? 3950
                let minV = model.snapshot.cellVoltages.min() ?? 3946
                let cellDelta = max(1, maxV - minV)
                let eggs: [String]
                if model.buddySkin == .arcReactor {
                    eggs = [
                        "🦾 Jarvis: 『Proof that Tony Stark has a heart.』電芯壓差僅 \(cellDelta)mV，方舟反應爐處於巔峰狀態！",
                        "🕶️ Tony Stark: 『賈維斯，有時候你得先學會跑，才能學會飛。』",
                        "⚡️ Jarvis: 『先生，方舟能源輸出已最佳化，Unibeam 單束光炮已準備就緒。』",
                        "🛡️ Jarvis: 『Mark 85 奈米裝甲待命中，反應爐功率輸出一切正常。』",
                        "💥 Tony Stark: 『我就是鋼鐵人（I am Iron Man）。』"
                    ]
                } else if model.buddySkin == .captainShield {
                    eggs = [
                        "🛡️ 隊長：『我可以跟你耗一整天（I can do this all day）。』電芯壓差僅 \(cellDelta)mV，防線固若金湯！",
                        "⚡️ 隊長：『復仇者，集結！（Avengers, assemble!）』",
                        "🛡️ 汎合金特性：完全吸收電壓衝擊與熱應力，80% 保護上限是最堅固的盾牌！",
                        "🇺🇸 隊長：『這塊盾牌象徵自由與堅持，主人今天也請全力以赴！』",
                        "🦾 隊長：『東尼，我們必須團結。』"
                    ]
                } else {
                    eggs = [
                        "✨ 秘密揭露：3 串電芯最大壓差僅 \(cellDelta)mV，均衡度媲美頂級實驗室！",
                        "🥰 今日已在桌面默默守護主人 \(model.continuousWorkMinutes) 分鐘啦！",
                        "🏆 守護評定：當前獲得【\(model.guardianLevel.title)】\(model.guardianLevel.stars) 榮譽認證！",
                        "💡 散熱小密技：把 Mac 底部架高 1 公分，電芯溫度能直接下降 2~3°C 喔！",
                        "⚡️ 戳得好舒服～本精靈滿電待命，隨時準備陪您衝刺下一個專案！"
                    ]
                }
                easterEggText = eggs.randomElement()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    isBubbleVisible = true
                    BatteryLoggerAppDelegate.updateBuddyPanelSize(isBubbleVisible: true)
                }
            }
            .onTapGesture(count: 1) {
                guard !isDragging else { return }
                easterEggText = nil
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    isBubbleVisible.toggle()
                    BatteryLoggerAppDelegate.updateBuddyPanelSize(isBubbleVisible: isBubbleVisible)
                }
            }
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.openHand.push()
                    if isDocked, let panel = BatteryLoggerAppDelegate.buddyPanel, let screen = panel.screen ?? NSScreen.main {
                        let visible = screen.visibleFrame
                        if panel.frame.minX < visible.minX {
                            panel.setFrameOrigin(NSPoint(x: visible.minX + 8, y: panel.frame.minY))
                        } else if panel.frame.maxX > visible.maxX {
                            panel.setFrameOrigin(NSPoint(x: visible.maxX - panel.frame.width - 8, y: panel.frame.minY))
                        }
                    }
                } else {
                    NSCursor.pop()
                }
            }
            .help("單擊展開提醒 · 雙擊戳戳旋轉彩蛋 · 長按隨意拖曳")
    }

    // MARK: - 5 Distinct Visual Avatar Skins

    @ViewBuilder
    private var avatarViewForCurrentSkin: some View {
        Group {
            switch model.buddySkin {
            case .classic:
                ClassicSkinView(
                    isCharging: isCharging,
                    percent: model.snapshot.percent,
                    emoji: moodDetails.emoji,
                    moodColor: moodDetails.color
                )
            case .pixelMonster:
                PixelMonsterSkinView(
                    isCharging: isCharging,
                    isDizzy: isDizzy,
                    percent: model.snapshot.percent
                )
            case .cyberCore:
                CyberCoreSkinView(
                    isCharging: isCharging,
                    isDizzy: isDizzy,
                    percent: model.snapshot.percent
                )
            case .arcReactor:
                ArcReactorSkinView(
                    isCharging: isCharging,
                    percent: model.snapshot.percent
                )
            case .captainShield:
                CaptainShieldSkinView(
                    isCharging: isCharging,
                    percent: model.snapshot.percent
                )
            }
        }
        .id(model.buddySkin)
    }
}

// MARK: - 1. Classic Glassy Aurora Orb Skin
struct ClassicSkinView: View {
    let isCharging: Bool
    let percent: Int?
    let emoji: String
    let moodColor: Color
    @Environment(\.colorScheme) private var colorScheme
    @State private var isBreathing = false

    var body: some View {
        ZStack {
            // Outer aura ring (Breathes gently in standby, rapid pulse when charging)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            moodColor.opacity(isBreathing ? (isCharging ? 0.65 : 0.40) : 0.18),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(
                    width: isBreathing ? (isCharging ? 74 : 69) : 63,
                    height: isBreathing ? (isCharging ? 74 : 69) : 63
                )

            // Inner glass circle
            Circle()
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.85))
                .frame(width: 56, height: 56)
                .shadow(
                    color: moodColor.opacity(isBreathing ? (isCharging ? 0.60 : 0.45) : 0.20),
                    radius: isBreathing ? (isCharging ? 10 : 8) : 4,
                    x: 0,
                    y: 3
                )
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    colorScheme == .dark ? Color.white.opacity(0.55) : Color.white.opacity(0.90),
                                    colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.14)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.75
                        )
                )

            // Character Emoji
            Text(emoji)
                .font(.system(size: 28))

            // Lightning or Sparkle Badge
            Image(systemName: isCharging ? "bolt.fill" : "sparkles")
                .font(.system(size: isCharging ? 11 : 13, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: isCharging ? [.yellow, .green] : [.purple, moodColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .scaleEffect(isBreathing ? (isCharging ? 1.25 : 1.05) : 0.95)
                .shadow(color: isCharging ? Color.green.opacity(isBreathing ? 0.8 : 0.3) : .clear, radius: isBreathing ? 5 : 1)
                .offset(x: 20, y: -20)

            // Battery percentage pill on the bottom
            Text(percent.map { "\($0)%" } ?? "—%")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(moodColor, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.35 : 0.6), lineWidth: 0.5)
                )
                .offset(y: 24)
        }
        .onAppear {
            startBreathing()
        }
        .onChange(of: isCharging) { _ in
            startBreathing()
        }
    }

    private func startBreathing() {
        isBreathing = false
        // Power saving: infinite 60fps animations only while charging; static glow otherwise.
        guard isCharging else {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { isBreathing = true }
            return
        }
        DispatchQueue.main.async {
            withAnimation(Animation.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
    }
}

// MARK: - 2. Retro 8-bit Pixel Battery Monster Skin
struct PixelMonsterSkinView: View {
    let isCharging: Bool
    let isDizzy: Bool
    let percent: Int?
    @State private var isBreathing = false

    var body: some View {
        ZStack {
            // Retro CRT screen outer bezel
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.88))
                .frame(width: 60, height: 60)
                .shadow(color: Color.green.opacity(isBreathing ? (isCharging ? 0.80 : 0.50) : 0.20), radius: isBreathing ? (isCharging ? 10 : 6) : 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(isCharging ? Color.green : Color.green.opacity(isBreathing ? 0.8 : 0.4), lineWidth: 1.5)
                )

            VStack(spacing: 2) {
                // Pixel Monster Face
                Text(isDizzy ? "😵" : (isCharging ? "👾" : "👾"))
                    .font(.system(size: 24))
                    .scaleEffect(isBreathing ? 1.06 : 0.95)

                // 8-bit Heart Health Bar
                Text(percent.map { "\($0)%" } ?? "—%")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundStyle(isCharging ? Color.green : Color.cyan)
            }

            // Top-right pixel status indicator
            Circle()
                .fill(isCharging ? Color.yellow : Color.green)
                .frame(width: 6, height: 6)
                .shadow(color: isCharging ? .yellow : .green, radius: isBreathing ? 4 : 1)
                .offset(x: 22, y: -22)
        }
        .onAppear {
            startBreathing()
        }
        .onChange(of: isCharging) { _ in
            startBreathing()
        }
    }

    private func startBreathing() {
        isBreathing = false
        // Power saving: infinite 60fps animations only while charging; static glow otherwise.
        guard isCharging else {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { isBreathing = true }
            return
        }
        DispatchQueue.main.async {
            withAnimation(Animation.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
    }
}

// MARK: - 3. Cyberpunk Techno Core Skin
struct CyberCoreSkinView: View {
    let isCharging: Bool
    let isDizzy: Bool
    let percent: Int?
    @State private var isBreathing = false
    @State private var isRotating = false

    var body: some View {
        ZStack {
            // Rotating Outer Techno Ring
            Circle()
                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(LinearGradient(colors: [.cyan, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 62, height: 62)
                .rotationEffect(.degrees(isRotating ? 360 : 0))

            // Inner Core Arc Reactor
            Circle()
                .fill(RadialGradient(colors: [Color.cyan.opacity(isBreathing ? 0.50 : 0.20), Color.black.opacity(0.85)], center: .center, startRadius: 2, endRadius: 28))
                .frame(width: 52, height: 52)
                .shadow(color: .cyan.opacity(isBreathing ? (isCharging ? 0.85 : 0.55) : 0.25), radius: isBreathing ? (isCharging ? 10 : 6) : 3)

            // High-tech Arc Symbol
            Text(isDizzy ? "🌀" : (isCharging ? "⚛️" : "💠"))
                .font(.system(size: 24))
                .scaleEffect(isBreathing ? 1.08 : 0.95)

            // Bottom Cyber HUD readout
            Text(percent.map { "\($0)%" } ?? "—%")
                .font(.system(size: 8.5, weight: .black, design: .monospaced))
                .foregroundStyle(.cyan)
                .padding(.horizontal, 4)
                .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 3))
                .offset(y: 22)
        }
        .onAppear {
            startBreathing()
        }
        .onChange(of: isCharging) { _ in
            startBreathing()
        }
    }

    private func startBreathing() {
        isBreathing = false
        // Power saving: infinite 60fps animations only while charging; static glow otherwise.
        guard isCharging else {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { isBreathing = true }
            return
        }
        DispatchQueue.main.async {
            withAnimation(Animation.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
            withAnimation(Animation.linear(duration: 4.0).repeatForever(autoreverses: false)) {
                isRotating = true
            }
        }
    }
}

// MARK: - 4. Iron Man Arc Reactor Skin (鋼鐵人方舟反應爐脈衝呼吸燈)
struct ArcReactorSkinView: View {
    let isCharging: Bool
    let percent: Int?
    @State private var isBreathing = false

    var body: some View {
        ZStack {
            // 1. High-energy Unibeam aura & Standby Breathing Plasma Halo
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.12, green: 0.85, blue: 1.0).opacity(isBreathing ? (isCharging ? 0.85 : 0.45) : (isCharging ? 0.35 : 0.12)),
                            Color.cyan.opacity(isBreathing ? (isCharging ? 0.45 : 0.22) : 0.05),
                            .clear
                        ],
                        center: .center,
                        startRadius: 16,
                        endRadius: 38
                    )
                )
                .frame(
                    width: isBreathing ? (isCharging ? 76 : 70) : (isCharging ? 66 : 62),
                    height: isBreathing ? (isCharging ? 76 : 70) : (isCharging ? 66 : 62)
                )

            // 2. Heavy Titanium / Gold Alloy Housing
            Circle()
                .fill(Color(red: 0.07, green: 0.09, blue: 0.13))
                .frame(width: 58, height: 58)
                .shadow(
                    color: Color.cyan.opacity(isBreathing ? (isCharging ? 0.90 : 0.65) : 0.25),
                    radius: isBreathing ? (isCharging ? 10 : 6) : 2.5
                )
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.88, green: 0.68, blue: 0.28),
                                    Color(red: 0.32, green: 0.37, blue: 0.44)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )

            // 3. 10 Segmented Magnetic Confinement Coils around perimeter
            ForEach(0..<10) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.96, green: 0.62, blue: 0.25),
                                Color(red: 0.65, green: 0.35, blue: 0.15)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3.5, height: 6.5)
                    .offset(y: -23)
                    .rotationEffect(.degrees(Double(i) * 36.0 + (isCharging && isBreathing ? 3.0 : 0.0)))
            }

            // 4. 10 Inter-coil Cyan Plasma Micro-Discharge Nodes (Breathing Spark Gaps)
            ForEach(0..<10) { i in
                Circle()
                    .fill(Color.cyan)
                    .frame(width: 2.2, height: 2.2)
                    .shadow(
                        color: .cyan,
                        radius: isBreathing ? (isCharging ? 3 : 2) : 0.5
                    )
                    .opacity(isBreathing ? (isCharging ? 1.0 : 0.90) : 0.20)
                    .offset(y: -23)
                    .rotationEffect(.degrees(Double(i) * 36.0 + 18.0))
            }

            // 5. Glowing Cyan Energy Laser Arc Ring
            Circle()
                .stroke(
                    Color.cyan.opacity(isBreathing ? (isCharging ? 1.0 : 0.95) : 0.45),
                    lineWidth: isBreathing ? (isCharging ? 2.2 : 1.8) : 1.2
                )
                .frame(width: 36, height: 36)
                .shadow(
                    color: .cyan.opacity(isBreathing ? (isCharging ? 0.95 : 0.85) : 0.25),
                    radius: isBreathing ? (isCharging ? 8 : 5) : 2
                )

            // 6. Center Palladium / Vibranium Triangular Core with Unibeam lens
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white,
                                Color(red: 0.10, green: 0.85, blue: 1.0),
                                Color(red: 0.02, green: 0.40, blue: 0.80)
                            ],
                            center: .center,
                            startRadius: 1,
                            endRadius: 12
                        )
                    )
                    .frame(width: 22, height: 22)
                    .scaleEffect(isBreathing ? (isCharging ? 1.15 : 1.06) : 0.94)
                    .shadow(
                        color: Color.cyan,
                        radius: isBreathing ? (isCharging ? 12 : 7) : 2.5
                    )

                Image(systemName: "triangle.fill")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(Color(red: 0.06, green: 0.10, blue: 0.15))
                    .rotationEffect(.degrees(180))

                Circle()
                    .fill(Color.white)
                    .frame(width: 4.5, height: 4.5)
                    .scaleEffect(isBreathing ? (isCharging ? 1.4 : 1.25) : 0.8)
                    .shadow(
                        color: .white,
                        radius: isBreathing ? (isCharging ? 4 : 3) : 1
                    )
            }

            // 7. Bottom Mark / Arc HUD Readout
            Text(percent.map { "ARC \($0)%" } ?? "ARC —%")
                .font(.system(size: 7.5, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color.cyan)
                .padding(.horizontal, 4)
                .padding(.vertical, 0.5)
                .background(Color.black.opacity(0.85), in: Capsule())
                .overlay(
                    Capsule().strokeBorder(Color.cyan.opacity(isBreathing ? 0.85 : 0.35), lineWidth: 0.5)
                )
                .offset(y: 24)
        }
        .onAppear {
            startBreathing()
        }
        .onChange(of: isCharging) { _ in
            startBreathing()
        }
    }

    private func startBreathing() {
        isBreathing = false
        // Power saving: infinite 60fps animations only while charging; static glow otherwise.
        guard isCharging else {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { isBreathing = true }
            return
        }
        DispatchQueue.main.async {
            withAnimation(Animation.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
    }
}

// MARK: - 5. Captain America Vibranium Energy Shield Skin
struct CaptainShieldSkinView: View {
    let isCharging: Bool
    let percent: Int?
    @State private var isBreathing = false

    var body: some View {
        ZStack {
            // Kinetic energy pulse aura when charging (汎合金能量擴散環)
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color.red, Color.blue, Color.white],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isCharging ? (isBreathing ? 2.5 : 1.0) : (isBreathing ? 1.2 : 0.4)
                )
                .frame(
                    width: isBreathing ? (isCharging ? 76 : 68) : (isCharging ? 64 : 62),
                    height: isBreathing ? (isCharging ? 76 : 68) : (isCharging ? 64 : 62)
                )
                .opacity(isBreathing ? (isCharging ? 0.85 : 0.35) : (isCharging ? 0.25 : 0.10))

            // Outer Crimson Red Vibranium Ring
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.92, green: 0.15, blue: 0.18),
                            Color(red: 0.65, green: 0.08, blue: 0.10)
                        ],
                        center: .center,
                        startRadius: 24,
                        endRadius: 30
                    )
                )
                .frame(width: 60, height: 60)
                .shadow(
                    color: Color.red.opacity(isBreathing ? (isCharging ? 0.70 : 0.45) : 0.20),
                    radius: isBreathing ? (isCharging ? 8 : 5) : 2.5
                )

            // Silver White Titanium Ring
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.95, green: 0.96, blue: 0.98),
                            Color(red: 0.78, green: 0.80, blue: 0.84)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 48, height: 48)

            // Middle Crimson Red Ring
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.92, green: 0.15, blue: 0.18),
                            Color(red: 0.65, green: 0.08, blue: 0.10)
                        ],
                        center: .center,
                        startRadius: 14,
                        endRadius: 20
                    )
                )
                .frame(width: 36, height: 36)

            // Deep Cobalt Blue Center Circle
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.12, green: 0.38, blue: 0.82),
                            Color(red: 0.05, green: 0.18, blue: 0.48)
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: 12
                    )
                )
                .frame(width: 24, height: 24)

            // Gleaming Silver Vibranium Star
            Image(systemName: "star.fill")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, Color(red: 0.82, green: 0.85, blue: 0.90)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .scaleEffect(isBreathing ? (isCharging ? 1.15 : 1.05) : 0.95)
                .shadow(color: .white.opacity(isBreathing ? (isCharging ? 0.9 : 0.6) : 0.25), radius: isBreathing ? 4 : 1.5)

            // Diagonal Metallic Specular Highlight
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.35), Color.clear, Color.black.opacity(0.25)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 60, height: 60)
                .allowsHitTesting(false)

            // Bottom Shield HUD Pill
            Text(percent.map { "CAP \($0)%" } ?? "CAP —%")
                .font(.system(size: 7.5, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 0.5)
                .background(Color(red: 0.08, green: 0.18, blue: 0.45).opacity(0.9), in: Capsule())
                .overlay(
                    Capsule().strokeBorder(Color.red.opacity(isBreathing ? 0.85 : 0.45), lineWidth: 0.5)
                )
                .offset(y: 24)
        }
        .onAppear {
            startBreathing()
        }
        .onChange(of: isCharging) { _ in
            startBreathing()
        }
    }

    private func startBreathing() {
        isBreathing = false
        // Power saving: infinite 60fps animations only while charging; static glow otherwise.
        guard isCharging else {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { isBreathing = true }
            return
        }
        DispatchQueue.main.async {
            withAnimation(Animation.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct MenuBarPanel: View {
    @EnvironmentObject private var model: BatteryModel
    @Environment(\.openWindow) private var openWindow

    private var percent: Int {
        model.snapshot.percent ?? 50
    }

    private var health: Double {
        model.snapshot.healthPercent ?? 100.0
    }

    private var temp: Double {
        model.snapshot.temperature ?? 25.0
    }

    private var cycles: Int {
        model.snapshot.cycles ?? 0
    }

    var body: some View {
        VStack(spacing: 9) {
            // 1. Top Header with App Title & Quick Settings
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.batteryblock.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                    Text("Battery Logger")
                        .font(.system(size: 13, weight: .bold))
                    Text("v2.0.0")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
                Spacer()
                HStack(spacing: 8) {
                    Button {
                        model.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("重新整理數據")

                    Button {
                        BatteryLoggerAppDelegate.showPreferencesWindow(model: model)
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("開啟偏好設定")
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)

            // 2. Hero Frosted Battery Card (Apple Translucent Glass)
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(percent)%")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Spacer()

                    HStack(spacing: 4) {
                        Circle()
                            .fill(model.snapshot.magSafeLedState.color)
                            .frame(width: 6, height: 6)
                        Text(model.snapshot.charging == true ? "充電中" : "外接電源旁路保護")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(model.snapshot.magSafeLedState.color)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(model.snapshot.magSafeLedState.color.opacity(0.12), in: Capsule())
                }

                // Apple-style Frosted Progress Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 8)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: model.displayChargeLimit < 100
                                        ? [Color.green.opacity(0.85), Color.mint]
                                        : [Color.blue.opacity(0.85), Color.cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * CGFloat(min(1.0, Double(percent) / 100.0)), height: 8)
                    }
                }
                .frame(height: 8)
            }
            .padding(11)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1.0)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1.5)

            // 3. Grid: Battery Health & MagSafe Status (Translucent Frosted Tiles)
            HStack(spacing: 8) {
                // Battery Health Card
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("電池健康度")
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.0f%% · %@", health, health >= 80 ? "優質" : "需保養"))
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    // Apple Watch Style Activity Ring
                    ZStack {
                        Circle()
                            .stroke(Color.primary.opacity(0.08), lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: CGFloat(min(1.0, health / 100.0)))
                            .stroke(
                                health >= 80 ? Color.green : Color.orange,
                                style: StrokeStyle(lineWidth: 3, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(health))%")
                            .font(.system(size: 7.5, weight: .bold, design: .rounded))
                    }
                    .frame(width: 25, height: 25)
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1.0)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 2.5, x: 0, y: 1)

                // MagSafe / Power Status Card
                VStack(alignment: .leading, spacing: 3) {
                    Text("供電來源握手")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(model.snapshot.magSafeLedState.color)
                            .frame(width: 6, height: 6)
                        Text(model.snapshot.magSafeLedState.title)
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(model.snapshot.magSafeLedState.color)
                            .lineLimit(1)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1.0)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 2.5, x: 0, y: 1)
            }

            // 4. Charge Limit & Bypass Protection Card (Frosted Mint Glass)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.green)
                        Text("充電保護上限 · \(model.displayChargeLimit)%")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.green)
                    }
                    Spacer()
                    Text(model.displayChargeLimitBadge ?? "旁路保護中")
                        .font(.system(size: 8.5, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Color.green.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.green)
                }

                Text(model.displayChargeLimitBadge != nil ? "\(model.displayChargeLimitBadge!) · 外接電源旁路保護" : "綠燈 MagSafe 旁路供電中 · 純外接供電保護電芯壽命")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)

                // Quick Switch Buttons (Glassmorphic Segmented Control)
                HStack(spacing: 5) {
                    Button("85% 保養") {
                        model.boostModeActive = false
                        model.setChargeLimit(85)
                    }
                    .buttonStyle(.bordered)
                    .tint(model.displayChargeLimit == 85 && !model.boostModeActive ? Color.green : Color.secondary)
                    .controlSize(.mini)

                    Button("90% 平衡") {
                        model.boostModeActive = false
                        model.setChargeLimit(90)
                    }
                    .buttonStyle(.bordered)
                    .tint(model.displayChargeLimit == 90 && !model.boostModeActive ? Color.blue : Color.secondary)
                    .controlSize(.mini)

                    Button(model.boostModeActive ? "衝刺中" : "100% 外出") {
                        model.activateBoostMode()
                    }
                    .buttonStyle(.bordered)
                    .tint(model.boostModeActive ? Color.orange : Color.secondary)
                    .controlSize(.mini)
                }
            }
            .padding(9)
            .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color.green.opacity(0.35), lineWidth: 1.0)
            )
            .shadow(color: Color.green.opacity(0.06), radius: 2.5, x: 0, y: 1)

            // 5. Battery Temp & Cycles Bar (Frosted Glass Tile)
            HStack(spacing: 8) {
                // Temperature
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("電池溫度")
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.1f°C", temp))
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(temp >= 35.0 ? Color.orange : Color.primary)
                    }
                    // Apple Clean Temperature Track
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.08))
                            let ratio = min(1.0, max(0.0, (temp - 20.0) / 25.0))
                            Capsule()
                                .fill(temp >= 35.0 ? Color.orange : Color.green.opacity(0.8))
                                .frame(width: max(6, geo.size.width * CGFloat(ratio)))
                        }
                    }
                    .frame(height: 4)
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1.0)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 2.5, x: 0, y: 1)

                // Cycles
                VStack(alignment: .leading, spacing: 2) {
                    Text("循環次數")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(cycles)")
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text(cycles < 300 ? "健康" : "正常")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.green)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1.0)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 2.5, x: 0, y: 1)
            }

            // 6. Action Dock Toolbar (Frosted Pill Buttons)
            HStack(spacing: 6) {
                Button {
                    BatteryLoggerAppDelegate.toggleBuddyWindow(model: model)
                } label: {
                    Label(model.buddySkin == .arcReactor ? "反應爐" : "精靈", systemImage: "sparkles")
                        .font(.system(size: 10, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    BatteryLoggerAppDelegate.showMainWindow()
                    openWindow(id: "main")
                } label: {
                    Label("主儀表", systemImage: "macwindow")
                        .font(.system(size: 10, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    BatteryLoggerAppDelegate.showPreferencesWindow(model: model)
                } label: {
                    Label("設定", systemImage: "gearshape")
                        .font(.system(size: 10, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(role: .destructive) {
                    model.stopRecording()
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.top, 2)
        }
        .padding(13)
        .frame(width: 314)
        .background(VisualEffectBackground(material: .popover, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1.0)
        )
    }
}

/// Categories for the Preferences Window
enum PreferencesTab: String, CaseIterable, Identifiable {
    case general = "一般與外觀"
    case notifications = "通知與 iMessage"
    case intelligence = "智能與 AI"
    case diagnostics = "診斷與科普"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape.2"
        case .notifications: return "bell.badge"
        case .intelligence: return "brain.head.profile"
        case .diagnostics: return "book.pages"
        }
    }
}

/// Comprehensive settings modal covering launch, notifications, display modes, buddy controls, and diagnostics with segmented tabs.
struct PreferencesSheet: View {
    @ObservedObject var model: BatteryModel
    @Environment(\.dismiss) private var dismiss
    var isStandaloneWindow: Bool = false
    @State private var selectedTab: PreferencesTab = .general

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("偏好設定")
                        .font(.headline)
                }
                Spacer()
                Button("完成") {
                    if isStandaloneWindow {
                        BatteryLoggerAppDelegate.preferencesWindow?.close()
                    } else {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Segmented Tab Picker
            Picker("偏好設定分頁", selection: $selectedTab) {
                ForEach(PreferencesTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 18)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedTab {
                    case .general:
                        generalTab
                    case .notifications:
                        notificationsTab
                    case .intelligence:
                        intelligenceTab
                    case .diagnostics:
                        diagnosticsTab
                    }
                }
                .padding(18)
            }
        }
        .frame(minWidth: 560, idealWidth: 600, minHeight: 520, idealHeight: 580)
    }

    // MARK: - 1. General & Appearance
    @ViewBuilder
    private var generalTab: some View {
        // 一般與系統啟動
        GroupBox("一般與系統啟動") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("開機登入時自動於背景啟動", isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.setLaunchAtLogin($0) }
                ))
                if model.launchAtLoginNeedsApproval {
                    Text("請在系統設定「一般」>「登入項目」中允許此 App。").font(.caption).foregroundStyle(.secondary)
                    Button("打開登入項目設定") { model.openLoginItemsSettings() }
                }
                Toggle("啟動 App 時自動顯示桌面電池精靈", isOn: $model.autoShowBuddyOnLaunch)
            }
            .padding(4)
        }

        // 選單列樣式
        GroupBox("選單列（狀態列）樣式") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("顯示模式", selection: $model.menuBarDisplayMode) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                Text("• 電池膠囊外框已動態跟隨 macOS 系統半透明風格（淺色 38% / 深色 48% 透光），柔和融入選單列。\n• 數字與 % 呈現純實體高對比字體，不帶任何彩度。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(4)
        }

        // 桌面電池精靈 (Desktop Buddy)
        GroupBox("桌面電池精靈（懸浮管家）") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("外觀造型主題", selection: $model.buddySkin) {
                    ForEach(BuddySkin.allCases) { skin in
                        Text(skin.displayName).tag(skin)
                    }
                }
                .pickerStyle(.menu)

                Toggle("靠近螢幕邊緣時自動磁吸探頭（微縮半臉不擋視野）", isOn: $model.edgeDockingEnabled)
                Toggle("鎖定精靈位置（防止滑鼠拖曳誤觸）", isOn: $model.buddyLocked)

                HStack {
                    Text("位置管理：")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("重設精靈位置至螢幕右下角") {
                        BatteryLoggerAppDelegate.resetBuddyPosition()
                    }
                    .controlSize(.small)
                }

                Text("• 雙擊精靈：360 度特技翻轉，隨機揭開電芯壓差、累計陪伴時間或彩蛋！\n• 甩動物理：拖曳快速甩動時精靈會短暫暈眩（😵‍💫）。\n• 智慧情境：自動辨識快充瓦數、放電暴增警報、90分鐘久坐喝水提醒（☕️）與深夜節律（💤）。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(4)
        }

        // 軟體版本與 GitHub 更新
        GroupBox("軟體版本與 GitHub 更新") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("目前版本：v2.0.0 (Build 50) · \(model.isAppleSilicon ? "Apple Silicon (ARM64)" : "Intel (x86_64)")")
                            .font(.subheadline.bold())
                        if let msg = UpdateChecker.shared.statusMessage {
                            Text(msg)
                                .font(.caption)
                                .foregroundStyle(UpdateChecker.shared.hasUpdate ? Color.orange : Color.secondary)
                        } else {
                            Text("開源專案：github.com/mic1491/Battery-Logger-macOS")
                                .font(.caption2)
                                .foregroundStyle(Color.secondary)
                        }
                    }
                    Spacer()
                    if UpdateChecker.shared.isChecking {
                        ProgressView().controlSize(.small)
                    } else if UpdateChecker.shared.hasUpdate, let url = UpdateChecker.shared.releaseURL {
                        Button("下載新版") {
                            NSWorkspace.shared.open(url)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.orange)
                        .controlSize(.small)
                    } else {
                        Button("檢查更新") {
                            UpdateChecker.shared.checkForUpdates(silent: false)
                        }
                        .controlSize(.small)
                    }
                }
            }
            .padding(4)
        }
    }

    // MARK: - 2. Notifications & iMessage
    @ViewBuilder
    private var notificationsTab: some View {
        // 系統通知與警報
        GroupBox("系統通知與警報") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("啟用系統原生通知橫幅", isOn: $model.notificationsEnabled)
                    .onChange(of: model.notificationsEnabled) { enabled in
                        if enabled { BatteryNotificationManager.shared.requestAuthorization() }
                    }
                if model.notificationsEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("達到保護上限時通知（如 85% / 90%）", isOn: $model.notifyOnLimitReached)
                        Toggle("電池高溫警報（溫度 ≥ 37°C 預防鼓包）", isOn: $model.notifyOnHighTemp)
                        Toggle("低電量預警（電量 ≤ 20% 避免過度放電）", isOn: $model.notifyOnLowBattery)
                    }
                    .padding(.leading, 18)
                }
            }
            .padding(4)
        }

        // 📱 iPhone iMessage 充電完成通知
        GroupBox("📱 iPhone iMessage 充電完成通知") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("充電達標時自動發送 iMessage 至 iPhone", isOn: $model.notifyIPhoneViaIMessage)
                    .font(.subheadline.bold())

                if model.notifyIPhoneViaIMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("接收對象（您的 iPhone 手機號碼或 Apple ID 信箱）：")
                                .font(.caption.bold())
                            HStack {
                                TextField("例如：0912345678 或 mic1491@gmail.com", text: $model.iPhoneIMessageTarget)
                                    .textFieldStyle(.roundedBorder)

                                Button(action: {
                                    model.sendTestIMessage()
                                }) {
                                    HStack(spacing: 4) {
                                        if model.isTestingIMessage {
                                            ProgressView().controlSize(.small)
                                        } else {
                                            Image(systemName: "paperplane.fill")
                                        }
                                        Text("發送測試")
                                    }
                                }
                                .disabled(model.iPhoneIMessageTarget.trimmingCharacters(in: .whitespaces).isEmpty || model.isTestingIMessage)
                            }
                        }

                        if let testResult = model.iMessageTestResult {
                            HStack(spacing: 5) {
                                Image(systemName: testResult.isSuccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                    .foregroundStyle(testResult.isSuccess ? Color.green : Color.red)
                                Text(testResult.message)
                                    .font(.caption)
                                    .foregroundStyle(testResult.isSuccess ? Color.green : Color.red)
                            }
                        }

                        Picker("通知觸發時機", selection: $model.iPhoneNotifyThreshold) {
                            ForEach(IPhoneNotifyThreshold.allCases) { threshold in
                                Text(threshold.displayName).tag(threshold)
                            }
                        }
                        .pickerStyle(.radioGroup)

                        Text("• 零額外安裝：由 Mac 內建 Messages 服務直接送出，iPhone 與 Apple Watch 會同步即時收到 iMessage 通知與震動。\n• 每次接上電源只在首次達標時通知一次，拔掉電源後自動重置。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 18)
                }
            }
            .padding(4)
        }

        // 🔌 智慧插座連動 (HomeKit / HTTP Webhook)
        GroupBox("🔌 智慧插座連動 (HomeKit / HTTP Webhook)") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("充電達上限時自動觸發智慧插座斷電", isOn: $model.smartPlugWebhookEnabled)
                    .font(.subheadline.bold())

                if model.smartPlugWebhookEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("達標斷電 Webhook URL：").font(.caption.bold())
                            HStack {
                                TextField("例如：http://192.168.1.50/relay/0?turn=off", text: $model.smartPlugTurnOffUrl)
                                    .textFieldStyle(.roundedBorder)
                                Button("測試斷電") {
                                    model.triggerSmartPlug(turnOff: true)
                                }
                                .controlSize(.small)
                            }
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text("低電量復電 Webhook URL：").font(.caption.bold())
                            HStack {
                                TextField("例如：http://192.168.1.50/relay/0?turn=on", text: $model.smartPlugTurnOnUrl)
                                    .textFieldStyle(.roundedBorder)
                                Button("測試復電") {
                                    model.triggerSmartPlug(turnOff: false)
                                }
                                .controlSize(.small)
                            }
                        }

                        Text("• 支援 Home Assistant, Tapo, Shelly, Eve, IFTTT 等支援 HTTP GET/POST 的區域網路或雲端智慧插座。\n• 達標時實體斷電，徹底免除充電頭長期插在牆壁待機之微量發熱。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 18)
                }
            }
            .padding(4)
        }
    }

    // MARK: - 3. Intelligence & AI
    @ViewBuilder
    private var intelligenceTab: some View {
        // 🧠 Google Gemini AI 智慧大腦設定
        GroupBox("🧠 Google Gemini AI 智慧大腦設定") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Gemini API Key：")
                        .font(.caption.bold())
                    Spacer()
                    Button("免費取得 API Key (Google AI Studio)") {
                        NSWorkspace.shared.open(URL(string: "https://aistudio.google.com/app/apikey")!)
                    }
                    .controlSize(.small)
                }

                HStack {
                    SecureField("在此貼上您的 Gemini API Key", text: Binding(
                        get: { GeminiService.shared.apiKey },
                        set: { GeminiService.shared.apiKey = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)

                    if !GeminiService.shared.apiKey.isEmpty {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.green)
                    }
                }

                HStack(spacing: 12) {
                    Picker("模型選擇", selection: Binding(
                        get: { GeminiService.shared.selectedModel },
                        set: { GeminiService.shared.selectedModel = $0 }
                    )) {
                        Text("Gemini 1.5 Flash (極速輕量，推薦)").tag("gemini-1.5-flash")
                        Text("Gemini 1.5 Pro (深度電化學推理)").tag("gemini-1.5-pro")
                        Text("Gemini 2.0 Flash (最新預覽)").tag("gemini-2.0-flash")
                    }
                    .pickerStyle(.menu)
                }

                Toggle("AI 回應完成後自動語音朗讀（J.A.R.V.I.S. 嗓音）", isOn: Binding(
                    get: { GeminiService.shared.autoSpeakResponse },
                    set: { GeminiService.shared.autoSpeakResponse = $0 }
                ))

                Text("• 零費用門檻：Google 提供個人開發者免費 API 呼叫額度。\n• 智慧大腦連動：啟用後，桌面精靈泡泡可自由提問，主畫面亦能一鍵生成全方位電化學體檢報告。")
                    .font(.caption2)
                    .foregroundStyle(Color.secondary)
            }
            .padding(4)
        }

        // 🤖 智能管家與自動化守護系統
        GroupBox("🤖 智能管家與自動化守護系統") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("語音播報系統（J.A.R.V.I.S. 嗓音 / 國語管家播報）", isOn: $model.voicePromptEnabled)
                    .font(.subheadline.bold())
                if model.voicePromptEnabled {
                    Text("• 切換「鋼鐵人方舟反應爐」造型時，將以 J.A.R.V.I.S. 經典英國腔（en-GB）進行能量狀態語音播報。\n• 其他皮膚造型將以溫暖管家國語（zh-TW）即時提醒插拔電、達標旁路與低電量。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 18)
                }

                Toggle("偷電怪獸偵探（背景異常高耗能程式即時通報與一鍵終止）", isOn: $model.rogueVampireDetectionEnabled)
                    .font(.subheadline.bold())
                if model.rogueVampireDetectionEnabled {
                    Text("• 當未插電且放電功率飆高時，自動揪出後台飆高 CPU 的惡意或未關閉程式，保護離線續航。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 18)
                }

                Toggle("行事曆預測外出與滿電衝刺建議（智慧掃描今日行程）", isOn: $model.calendarOutingPredictionEnabled)
                    .font(.subheadline.bold())
                if model.calendarOutingPredictionEnabled {
                    Text("• 自動掃描行事曆會議與差旅外出，於出發前及早提醒開啟衝刺模式充至 100%。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 18)
                }
            }
            .padding(4)
        }

        // ⏰ 定時出門滿電衝刺預約
        GroupBox("⏰ 定時出門滿電衝刺預約 (Departure Schedule)") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("每日出門前自動 100% 滿電衝刺", isOn: $model.departureScheduleEnabled)
                    .font(.subheadline.bold())

                if model.departureScheduleEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("預定出發時間（24小時制，如 08:30）：")
                                .font(.caption.bold())
                            TextField("08:30", text: $model.departureTimeString)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                        }

                        Text("• 智慧避開夜間高壓：整夜插電時維持 85% 低應力保養，在出發前 60 分鐘自動啟動滿電衝刺，讓您出門時恰好 100% 滿電。\n• 出門拔掉電源線後，自動回歸 85% 保養上限。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 18)
                }
            }
            .padding(4)
        }

        // ⚡️ Apple 捷徑 (Shortcuts) 與 Siri URL Scheme
        GroupBox("⚡️ Apple 捷徑 (Shortcuts) 與 Siri URL Scheme") {
            VStack(alignment: .leading, spacing: 8) {
                Text("支援由 Apple「捷徑」App 或終端機直接透過 URL Scheme 指令控制 Mac 電池：")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("• 解鎖 100% 衝刺：`open \"batterylogger://boost\"`")
                    Text("• 設定 80% 上限：`open \"batterylogger://limit?value=80\"`")
                    Text("• 切換主動放電：`open \"batterylogger://discharge\"`")
                    Text("• 切換航行保護：`open \"batterylogger://sailing\"`")
                }
                .font(.system(size: 11, design: .monospaced))
                .padding(6)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))

                Button("複製 Siri 捷徑 Open URL 範例") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("batterylogger://boost", forType: .string)
                }
                .controlSize(.small)
            }
            .padding(4)
        }

        // 🛡️ 開機登入前 SMC 守護 (FileVault 保障)
        GroupBox("🛡️ 開機登入前 SMC 守護 (FileVault 保障)") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("全天候 SMC 底層守護進程 (LaunchDaemon)")
                            .font(.subheadline.bold())
                        Text(model.isLaunchDaemonInstalled ? "✅ 守護已安裝：重開機停留在登入密碼畫面時，依然自動維持 \(model.userTargetLimit)% 充電上限。" : "尚未安裝：開機卡在 FileVault 畫面未進入桌面時可能充過 \(model.userTargetLimit)%。")
                            .font(.caption2)
                            .foregroundStyle(model.isLaunchDaemonInstalled ? Color.green : Color.secondary)
                    }
                    Spacer()
                    if model.isLaunchDaemonInstalled {
                        Button("解除安裝") {
                            model.uninstallLaunchDaemonHelper()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Button("安裝守護進程") {
                            model.installLaunchDaemonHelper()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
            .padding(4)
        }

        // 🔑 免輸入密碼特權 Helper (SUID 靜默授權)
        GroupBox("🔑 免輸入密碼特權 Helper (SUID 靜默授權)") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("全自動靜默切換輔助工具 (/usr/local/bin/smc-battery-tool)")
                            .font(.subheadline.bold())
                        Text(model.isPrivilegedHelperInstalled ? "✅ 已安裝特權工具：所有充電上限切換、航行滑行與底座模式皆靜默完成，不再跳出 macOS 密碼框！" : "尚未安裝：每次背景調節時若遇權限不足可能彈出密碼授權。")
                            .font(.caption2)
                            .foregroundStyle(model.isPrivilegedHelperInstalled ? Color.green : Color.secondary)
                    }
                    Spacer()
                    if model.isPrivilegedHelperInstalled {
                        Button("解除安裝") {
                            model.uninstallPrivilegedHelper()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Button("一鍵安裝免密碼 Helper") {
                            model.installPrivilegedHelper()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
            .padding(4)
        }

        // 🍃 macOS 低耗電模式自動化
        GroupBox("🍃 macOS 低耗電模式自動化 (Low Power Mode)") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("電量低於 20% 且拔電時，自動啟用 macOS「低耗電模式」", isOn: $model.autoLowPowerModeEnabled)
                    .font(.subheadline.bold())

                Text("• 外出電池電量告急時，自動限制晶片能耗與螢幕高刷，為您爭取約 1 小時外出續航。\n• 重新插上充電器時，自動退出低耗電模式並恢復最高效能。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 18)
            }
            .padding(4)
        }
    }

    // MARK: - 4. Diagnostics & Science Knowledge
    @ViewBuilder
    private var diagnosticsTab: some View {
        // 診斷報告導出
        GroupBox("診斷與技術報表") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("完整電池硬體診斷報告").font(.subheadline.bold())
                    Text("包含各電芯壓差、循環階段、SMC 狀態之純文字完整技術報告。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("匯出報告...") {
                    model.exportDiagnosticReport()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(4)
        }

        // 鋰電池循環原理與科學保養指南
        GroupBox("鋰電池循環原理與科學保養指南") {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Q1: 怎麼充電會增加循環次數？")
                        .font(.caption.bold())
                        .foregroundStyle(.primary)
                    Text("• 循環次數是「累計 100% 總電量吞吐」才算一次，並非插拔次數！\n• 例如：從 30% 充到 80%（僅使用 50% 額度），需連續兩次才累計為 1 次循環。\n• 隨充隨用完全不會增加額外循環，請放心隨時充電！")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 3) {
                    Text("Q2: 為什麼建議一次充到 80%？（淺充保護）")
                        .font(.caption.bold())
                        .foregroundStyle(.primary)
                    Text("• 鋰離子電池最舒適的電壓區間為 30% ~ 80%（~3.85V ~ 4.05V）。\n• 當充超過 85% 時，電芯電壓會攀升至 4.2V~4.35V 極限高壓，容易加速電解液氧化並導致微膨脹。\n• 養成「30% 隨手充、80% 旁路斷電」的習慣，可讓電池有效使用年限延長 2 至 3 倍！")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 3) {
                    Text("Q3: 最傷電池的充電方式是什麼？")
                        .font(.caption.bold())
                        .foregroundStyle(.primary)
                    Text("• ① 深度過度放電（用到 0% 自動關機才充，負極銅箔易析出永久損壞）。\n• ② 高溫快充（邊充邊高負載或機身 >36°C，化學反應劇烈加劇衰減）。\n• ③ 長年 100% 插電滿載無限制（電芯長期待在 4.3V 極限高壓）。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(4)
        }
    }
}
