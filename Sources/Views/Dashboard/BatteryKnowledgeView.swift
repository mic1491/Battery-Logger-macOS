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
