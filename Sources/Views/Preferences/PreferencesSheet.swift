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
