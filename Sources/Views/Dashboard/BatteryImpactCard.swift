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

struct BatteryImpactCard: View {
    let analysis: BatteryImpactAnalysis

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: analysis.level.icon)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(analysis.level.color)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(analysis.title)
                                .font(.headline)
                                .foregroundStyle(analysis.level.color)

                            Spacer()

                            Text(analysis.cellVoltageEstimate)
                                .font(.caption.monospacedDigit())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.primary.opacity(0.08), in: Capsule())
                        }
                        Text(analysis.description)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                }

                Divider()

                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text(analysis.suggestion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
        } label: {
            Label("目前狀態對電池之影響評估", systemImage: "waveform.path.ecg")
                .font(.headline)
        }
    }
}

