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

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case iconAndPercent = "icon_percent"
    case iconOnly = "icon_only"
    case percentOnly = "percent_only"
    case iconAndRemainingTime = "icon_time"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .iconAndPercent: return "圖示 ＋ 百分比"
        case .iconOnly: return "僅電池圖示"
        case .percentOnly: return "僅百分比"
        case .iconAndRemainingTime: return "圖示 ＋ 剩餘時間"
        }
    }
}

/// Visual skin theme for the desktop battery buddy.
enum BuddySkin: String, CaseIterable, Identifiable {
    case classic = "classic"
    case pixelMonster = "pixel"
    case cyberCore = "cyber"
    case arcReactor = "arc_reactor"
    case captainShield = "captain_shield"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .classic: return "經典靈動光球 🔮"
        case .pixelMonster: return "復古像素電池怪 👾"
        case .cyberCore: return "賽博微型反應堆 ⚛️"
        case .arcReactor: return "鋼鐵人方舟反應爐 🦾"
        case .captainShield: return "美國隊長汎合金之盾 🛡️"
        }
    }
}

/// A persistent daily record of battery health, capacity retention, and cycle count.

enum IPhoneNotifyThreshold: String, CaseIterable, Identifiable {
    case atLimit = "atLimit"
    case at100 = "at100"
    case both = "both"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .atLimit:
            return "達到設定的充電上限時通知（例如 80% / 85% / 90%）"
        case .at100:
            return "達到 100% 完全充飽時通知"
        case .both:
            return "充電上限與 100% 充飽時皆通知"
        }
    }
}

enum DashboardTab: String, CaseIterable, Identifiable {
    case overview = "⚡️ 能源概覽"
    case intelligence = "🧠 智能守護與 AI"
    case diagnostics = "🔬 深度技術與分析"

    var id: String { rawValue }
}


/// Categories for the Preferences Window
enum PreferencesTab: String, CaseIterable, Identifiable {
    case general = "一般與外觀"
    case notifications = "通知與 iMessage"
    case intelligence = "智能與 AI"
    case diagnostics = "診斷與科普"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape.2"
        case .notifications: return "bell.badge"
        case .intelligence: return "brain.head.profile"
        case .diagnostics: return "book.pages"
        }
    }
}

