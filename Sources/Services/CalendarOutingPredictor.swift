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
