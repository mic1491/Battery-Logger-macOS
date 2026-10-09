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
