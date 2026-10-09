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
