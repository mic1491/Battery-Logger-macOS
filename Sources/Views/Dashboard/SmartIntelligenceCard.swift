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
