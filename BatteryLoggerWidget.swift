import SwiftUI
import WidgetKit
import Charts
import IOKit
import IOKit.ps

private struct BatteryWidgetEntry: TimelineEntry {
    let date: Date
    let percent: Int?
    let pluggedIn: Bool
    let charging: Bool
    let full: Bool
    let health: Int?
    let samples: [BatteryWidgetSample]
    var details = BatteryWidgetDetails()
}

private struct BatteryWidgetDetails {
    var fullCapacity: Int?
    var designCapacity: Int?
    var cycles: Int?
    var temperature: Double?
    var volts: Double?
    var amps: Double?
    var timeToEmpty: Int?
    var timeToFull: Int?

    var watts: Double? {
        guard let volts, let amps else { return nil }
        return abs(volts * amps)
    }

    static func validMinutes(_ value: Int?) -> Int? {
        guard let value, value > 0, value < 65535 else { return nil }
        return value
    }
}

private struct BatteryWidgetSample: Codable, Identifiable {
    let time: Date
    let percent: Int
    var id: Date { time }
}

private enum BatteryWidgetData {
    static let historyKey = "battery-widget-history-v1"

    static func read() -> (percent: Int?, pluggedIn: Bool, charging: Bool, full: Bool, health: Int?, details: BatteryWidgetDetails) {
        var percent: Int?
        var plugged = false
        var charging = false
        var full = false
        var details = BatteryWidgetDetails()

        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in list {
                guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else { continue }
                guard desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
                details.timeToEmpty = BatteryWidgetDetails.validMinutes((desc[kIOPSTimeToEmptyKey] as? NSNumber)?.intValue)
                details.timeToFull = BatteryWidgetDetails.validMinutes((desc[kIOPSTimeToFullChargeKey] as? NSNumber)?.intValue)
                let current = (desc[kIOPSCurrentCapacityKey] as? NSNumber)?.intValue
                let maximum = (desc[kIOPSMaxCapacityKey] as? NSNumber)?.intValue
                if let current, let maximum, maximum > 0 {
                    percent = max(0, min(100, Int((Double(current) / Double(maximum) * 100).rounded())))
                } else if let current {
                    percent = max(0, min(100, current))
                }
                if let state = desc[kIOPSPowerSourceStateKey] as? String {
                    plugged = state == kIOPSACPowerValue
                }
                charging = (desc[kIOPSIsChargingKey] as? NSNumber)?.boolValue ?? false
                full = (desc[kIOPSIsChargedKey] as? NSNumber)?.boolValue ?? false
            }
        }

        var health: Int?
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != IO_OBJECT_NULL {
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dictionary = properties?.takeRetainedValue() as? [String: Any] {
                func number(_ key: String) -> Int? {
                    guard let value = dictionary[key] as? NSNumber else { return nil }
                    return Int(truncatingIfNeeded: value.int64Value)
                }
                // MaxCapacity is a percentage on some Macs. Only use actual mAh values.
                details.fullCapacity = [number("AppleRawMaxCapacity"), number("NominalChargeCapacity"), number("MaxCapacity")]
                    .compactMap { $0 }.first { $0 > 100 }
                details.designCapacity = number("DesignCapacity").flatMap { $0 > 100 ? $0 : nil }
                if let maximum = details.fullCapacity, let design = details.designCapacity {
                    health = max(0, min(100, Int((Double(maximum) / Double(design) * 100).rounded())))
                }
                details.cycles = number("CycleCount").flatMap { $0 >= 0 ? $0 : nil }
                details.temperature = number("Temperature").map { Double($0) / 100 }
                    .flatMap { (-20...100).contains($0) ? $0 : nil }
                details.volts = number("Voltage").map { Double($0) / 1000 }
                    .flatMap { (0.1...30).contains($0) ? $0 : nil }
                details.amps = number("Amperage").map { Double($0) / 1000 }
                    .flatMap { abs($0) <= 50 ? $0 : nil }
                details.timeToEmpty = details.timeToEmpty ?? BatteryWidgetDetails.validMinutes(number("AvgTimeToEmpty"))
                details.timeToFull = details.timeToFull ?? BatteryWidgetDetails.validMinutes(number("AvgTimeToFull"))
                if let uiPercent = number("UISoc"), (0...100).contains(uiPercent) { percent = uiPercent }
            }
            IOObjectRelease(service)
        }
        return (percent, plugged, charging, full, health, details)
    }

    static func makeEntry() -> BatteryWidgetEntry {
        let current = read()
        var history = loadHistory()
        if let percent = current.percent {
            let now = Date()
            if history.last.map({ now.timeIntervalSince($0.time) >= 10 * 60 }) ?? true {
                history.append(BatteryWidgetSample(time: now, percent: percent))
            } else if !history.isEmpty {
                history[history.count - 1] = BatteryWidgetSample(time: now, percent: percent)
            }
            history = history.filter { now.timeIntervalSince($0.time) <= 24 * 60 * 60 }
            saveHistory(history)
        }
        return BatteryWidgetEntry(date: Date(), percent: current.percent, pluggedIn: current.pluggedIn,
                                  charging: current.charging, full: current.full, health: current.health,
                                  samples: history, details: current.details)
    }

    static func loadHistory() -> [BatteryWidgetSample] {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let samples = try? JSONDecoder().decode([BatteryWidgetSample].self, from: data) else { return [] }
        return samples
    }

    static func saveHistory(_ samples: [BatteryWidgetSample]) {
        guard let data = try? JSONEncoder().encode(samples) else { return }
        UserDefaults.standard.set(data, forKey: historyKey)
    }

    static func stateText(_ entry: BatteryWidgetEntry) -> String {
        if entry.pluggedIn && entry.full { return "電源轉接器 · 電池已充滿" }
        if entry.pluggedIn && entry.charging { return "電源轉接器 · 正在充電" }
        if entry.pluggedIn { return "電源轉接器 · 暫停充電" }
        return "電池供電 · 正在放電"
    }
}

private struct BatteryWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> BatteryWidgetEntry {
        BatteryWidgetEntry(date: .now, percent: 82, pluggedIn: true, charging: false, full: false,
                           health: 94, samples: (0..<8).map { index in
            BatteryWidgetSample(time: .now.addingTimeInterval(Double(index - 8) * 3600), percent: 96 - index * 2)
        }, details: BatteryWidgetDetails(fullCapacity: 4794, designCapacity: 5100, cycles: 286,
                                         temperature: 31.2, volts: 11.6, amps: -0.82,
                                         timeToEmpty: 245, timeToFull: nil))
    }

    func getSnapshot(in context: Context, completion: @escaping (BatteryWidgetEntry) -> Void) {
        completion(BatteryWidgetData.makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteryWidgetEntry>) -> Void) {
        let entry = BatteryWidgetData.makeEntry()
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3 * 60))))
    }
}

private struct BatteryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BatteryWidgetEntry

    private var stateSymbol: String {
        if entry.pluggedIn && entry.full { return "powerplug.fill" }
        if entry.pluggedIn && entry.charging { return "bolt.fill" }
        if entry.pluggedIn { return "powerplug" }
        return "battery.100percent"
    }

    private var stateColor: Color {
        if entry.pluggedIn && entry.charging { return .green }
        if !entry.pluggedIn && (entry.percent ?? 100) <= 20 { return .orange }
        return .secondary
    }

    var body: some View {
        Group {
            if family == .systemLarge { large }
            else if family == .systemSmall { small } else { medium }
        }
        .padding(14)
        .containerBackground(.background, for: .widget)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: stateSymbol).foregroundStyle(stateColor)
                Text("電池記錄器").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(entry.percent.map { "\($0)%" } ?? "—")
                .font(.system(size: 38, weight: .semibold, design: .rounded)).contentTransition(.numericText())
            Text(BatteryWidgetData.stateText(entry))
                .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            if let health = entry.health {
                Text("健康度 \(health)%").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: stateSymbol).foregroundStyle(stateColor)
                    Text("目前電量").font(.caption).foregroundStyle(.secondary)
                }
                Text(entry.percent.map { "\($0)%" } ?? "—")
                    .font(.system(size: 34, weight: .semibold, design: .rounded)).contentTransition(.numericText())
                Text(BatteryWidgetData.stateText(entry))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if let health = entry.health {
                    Text("健康度 \(health)%").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 145, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text("近 24 小時電量").font(.caption).foregroundStyle(.secondary)
                if entry.samples.count >= 2 {
                    Chart(entry.samples) { sample in
                        AreaMark(x: .value("時間", sample.time), y: .value("電量", sample.percent))
                            .foregroundStyle(.green.opacity(0.14))
                        LineMark(x: .value("時間", sample.time), y: .value("電量", sample.percent))
                            .foregroundStyle(.green).lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    }
                    .chartYScale(domain: 0...100)
                    .chartYAxis(.hidden)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 3)) { value in
                            AxisValueLabel(format: .dateTime.hour())
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        Image(systemName: "chart.xyaxis.line").foregroundStyle(.green)
                        Text("趨勢會隨小工具更新逐步累積")
                            .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
                Text("更新時間：\(entry.date.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private var powerLabel: String {
        guard let amps = entry.details.amps else { return "電池功率" }
        if amps > 0.05 { return "充入電池" }
        if amps < -0.05 { return "電池放電" }
        return "電池功率"
    }

    private var estimatedTime: String {
        if entry.pluggedIn && entry.full { return "已充滿" }
        if entry.pluggedIn && !entry.charging { return "暫停充電" }
        let minutes = entry.charging ? entry.details.timeToFull : entry.details.timeToEmpty
        guard let minutes else { return "估算中" }
        if minutes < 60 { return "約 \(minutes) 分" }
        return "約 \(minutes / 60) 時 \(minutes % 60) 分"
    }

    private func detailCell(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text(entry.percent.map { "\($0)%" } ?? "—")
                    .font(.system(size: 40, weight: .semibold, design: .rounded)).monospacedDigit()
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 5) {
                    Label("電池詳細資訊", systemImage: stateSymbol)
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(stateColor)
                    Text(entry.percent == nil ? "未偵測到內建電池" : BatteryWidgetData.stateText(entry))
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                }
            }

            HStack(spacing: 12) {
                detailCell(powerLabel, entry.details.watts.map { String(format: "%.1f W", $0) } ?? "未提供")
                detailCell(entry.charging ? "預估充滿時間" : "預估可用時間", entry.percent == nil ? "未提供" : estimatedTime)
            }
            .padding(9)
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), alignment: .leading, spacing: 10) {
                detailCell("健康度（容量估算）", entry.health.map { "\($0)%" } ?? "未提供")
                detailCell("循環次數", entry.details.cycles.map { "\($0) 次" } ?? "未提供")
                detailCell("電池溫度", entry.details.temperature.map { String(format: "%.1f °C", $0) } ?? "未提供")
                detailCell("目前最大容量", entry.details.fullCapacity.map { "\($0) mAh" } ?? "未提供")
                detailCell("設計容量", entry.details.designCapacity.map { "\($0) mAh" } ?? "未提供")
                detailCell("電池電壓", entry.details.volts.map { String(format: "%.2f V", $0) } ?? "未提供")
            }

            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("近 24 小時電量").font(.system(size: 10)).foregroundStyle(.secondary)
                if entry.samples.count >= 2 {
                    Chart(entry.samples) { sample in
                        AreaMark(x: .value("時間", sample.time), y: .value("電量", sample.percent))
                            .foregroundStyle(.green.opacity(0.12))
                        LineMark(x: .value("時間", sample.time), y: .value("電量", sample.percent))
                            .foregroundStyle(.green).lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                    .chartYScale(domain: 0...100)
                    .chartXScale(domain: entry.date.addingTimeInterval(-86400)...entry.date)
                    .chartYAxis(.hidden)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                            AxisValueLabel(format: .dateTime.hour())
                        }
                    }
                    .frame(minHeight: 48, maxHeight: .infinity)
                } else {
                    Text("趨勢會隨小工具更新逐步累積")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 48, maxHeight: .infinity, alignment: .center)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("更新：\(entry.date.formatted(date: .omitted, time: .shortened)) · 由系統排程更新")
                Text("功率為電池端讀值，非插座耗電量")
            }
            .font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

}

struct BatterySmallWidget: Widget {
    let kind = "BatteryLoggerSmallWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BatteryWidgetProvider()) { entry in
            BatteryWidgetView(entry: entry)
        }
        .configurationDisplayName("電池摘要")
        .description("查看目前電量、電源狀態與電池健康度。")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

struct BatteryMediumWidget: Widget {
    let kind = "BatteryLoggerMediumWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BatteryWidgetProvider()) { entry in
            BatteryWidgetView(entry: entry)
        }
        .configurationDisplayName("電量趨勢")
        .description("查看目前電源狀態與逐步累積的 24 小時電量趨勢。")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

struct BatteryLargeWidget: Widget {
    let kind = "BatteryLoggerLargeWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BatteryWidgetProvider()) { entry in
            BatteryWidgetView(entry: entry)
        }
        .configurationDisplayName("電池詳細資訊")
        .description("電量、電池功率、預估時間、健康度、循環次數、容量、溫度與 24 小時趨勢。")
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
    }
}

@main
struct BatteryLoggerWidgetBundle: WidgetBundle {
    var body: some Widget {
        BatterySmallWidget()
        BatteryMediumWidget()
        BatteryLargeWidget()
    }
}
