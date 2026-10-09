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
