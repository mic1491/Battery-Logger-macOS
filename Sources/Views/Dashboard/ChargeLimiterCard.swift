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
