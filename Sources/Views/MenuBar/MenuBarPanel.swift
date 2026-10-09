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

struct MenuBarPanel: View {
    @EnvironmentObject private var model: BatteryModel
    @Environment(\.openWindow) private var openWindow

    private var percent: Int {
        model.snapshot.percent ?? 50
    }

    private var health: Double {
        model.snapshot.healthPercent ?? 100.0
    }

    private var temp: Double {
        model.snapshot.temperature ?? 25.0
    }

    private var cycles: Int {
        model.snapshot.cycles ?? 0
    }

    var body: some View {
        VStack(spacing: 9) {
            // 1. Top Header with App Title & Quick Settings
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.batteryblock.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                    Text("Battery Logger")
                        .font(.system(size: 13, weight: .bold))
                    Text("v2.0.0")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
                Spacer()
                HStack(spacing: 8) {
                    Button {
                        model.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("重新整理數據")

                    Button {
                        BatteryLoggerAppDelegate.showPreferencesWindow(model: model)
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("開啟偏好設定")
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)

            // 2. Hero Frosted Battery Card (Apple Translucent Glass)
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(percent)%")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Spacer()

                    HStack(spacing: 4) {
                        Circle()
                            .fill(model.snapshot.magSafeLedState.color)
                            .frame(width: 6, height: 6)
                        Text(model.snapshot.charging == true ? "充電中" : "外接電源旁路保護")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(model.snapshot.magSafeLedState.color)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(model.snapshot.magSafeLedState.color.opacity(0.12), in: Capsule())
                }

                // Apple-style Frosted Progress Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 8)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: model.displayChargeLimit < 100
                                        ? [Color.green.opacity(0.85), Color.mint]
                                        : [Color.blue.opacity(0.85), Color.cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * CGFloat(min(1.0, Double(percent) / 100.0)), height: 8)
                    }
                }
                .frame(height: 8)
            }
            .padding(11)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1.0)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1.5)

            // 3. Grid: Battery Health & MagSafe Status (Translucent Frosted Tiles)
            HStack(spacing: 8) {
                // Battery Health Card
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("電池健康度")
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.0f%% · %@", health, health >= 80 ? "優質" : "需保養"))
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    // Apple Watch Style Activity Ring
                    ZStack {
                        Circle()
                            .stroke(Color.primary.opacity(0.08), lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: CGFloat(min(1.0, health / 100.0)))
                            .stroke(
                                health >= 80 ? Color.green : Color.orange,
                                style: StrokeStyle(lineWidth: 3, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(health))%")
                            .font(.system(size: 7.5, weight: .bold, design: .rounded))
                    }
                    .frame(width: 25, height: 25)
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1.0)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 2.5, x: 0, y: 1)

                // MagSafe / Power Status Card
                VStack(alignment: .leading, spacing: 3) {
                    Text("供電來源握手")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(model.snapshot.magSafeLedState.color)
                            .frame(width: 6, height: 6)
                        Text(model.snapshot.magSafeLedState.title)
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(model.snapshot.magSafeLedState.color)
                            .lineLimit(1)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1.0)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 2.5, x: 0, y: 1)
            }

            // 4. Charge Limit & Bypass Protection Card (Frosted Mint Glass)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.green)
                        Text("充電保護上限 · \(model.displayChargeLimit)%")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.green)
                    }
                    Spacer()
                    Text(model.displayChargeLimitBadge ?? "旁路保護中")
                        .font(.system(size: 8.5, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Color.green.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.green)
                }

                Text(model.displayChargeLimitBadge != nil ? "\(model.displayChargeLimitBadge!) · 外接電源旁路保護" : "綠燈 MagSafe 旁路供電中 · 純外接供電保護電芯壽命")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)

                // Quick Switch Buttons (Glassmorphic Segmented Control)
                HStack(spacing: 5) {
                    Button("85% 保養") {
                        model.boostModeActive = false
                        model.setChargeLimit(85)
                    }
                    .buttonStyle(.bordered)
                    .tint(model.displayChargeLimit == 85 && !model.boostModeActive ? Color.green : Color.secondary)
                    .controlSize(.mini)

                    Button("90% 平衡") {
                        model.boostModeActive = false
                        model.setChargeLimit(90)
                    }
                    .buttonStyle(.bordered)
                    .tint(model.displayChargeLimit == 90 && !model.boostModeActive ? Color.blue : Color.secondary)
                    .controlSize(.mini)

                    Button(model.boostModeActive ? "衝刺中" : "100% 外出") {
                        model.activateBoostMode()
                    }
                    .buttonStyle(.bordered)
                    .tint(model.boostModeActive ? Color.orange : Color.secondary)
                    .controlSize(.mini)
                }
            }
            .padding(9)
            .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color.green.opacity(0.35), lineWidth: 1.0)
            )
            .shadow(color: Color.green.opacity(0.06), radius: 2.5, x: 0, y: 1)

            // 5. Battery Temp & Cycles Bar (Frosted Glass Tile)
            HStack(spacing: 8) {
                // Temperature
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("電池溫度")
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.1f°C", temp))
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(temp >= 35.0 ? Color.orange : Color.primary)
                    }
                    // Apple Clean Temperature Track
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.08))
                            let ratio = min(1.0, max(0.0, (temp - 20.0) / 25.0))
                            Capsule()
                                .fill(temp >= 35.0 ? Color.orange : Color.green.opacity(0.8))
                                .frame(width: max(6, geo.size.width * CGFloat(ratio)))
                        }
                    }
                    .frame(height: 4)
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1.0)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 2.5, x: 0, y: 1)

                // Cycles
                VStack(alignment: .leading, spacing: 2) {
                    Text("循環次數")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(cycles)")
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text(cycles < 300 ? "健康" : "正常")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.green)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1.0)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 2.5, x: 0, y: 1)
            }

            // 6. Action Dock Toolbar (Frosted Pill Buttons)
            HStack(spacing: 6) {
                Button {
                    BatteryLoggerAppDelegate.toggleBuddyWindow(model: model)
                } label: {
                    Label(model.buddySkin == .arcReactor ? "反應爐" : "精靈", systemImage: "sparkles")
                        .font(.system(size: 10, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    BatteryLoggerAppDelegate.showMainWindow()
                    openWindow(id: "main")
                } label: {
                    Label("主儀表", systemImage: "macwindow")
                        .font(.system(size: 10, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    BatteryLoggerAppDelegate.showPreferencesWindow(model: model)
                } label: {
                    Label("設定", systemImage: "gearshape")
                        .font(.system(size: 10, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(role: .destructive) {
                    model.stopRecording()
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.top, 2)
        }
        .padding(13)
        .frame(width: 314)
        .background(VisualEffectBackground(material: .popover, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1.0)
        )
    }
}
