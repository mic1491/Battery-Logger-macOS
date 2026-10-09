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
