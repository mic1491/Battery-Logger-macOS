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

struct InfoCard: View {
    let title: String
    let icon: String
    var iconColor: Color? = nil
    let rows: [(String, String)]
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(rows.indices, id: \.self) { i in
                    HStack(alignment: .firstTextBaseline) {
                        Text(rows[i].0).foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
                        Text(rows[i].1).textSelection(.enabled).lineLimit(2)
                        Spacer(minLength: 0)
                    }.font(.callout)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
        } label: {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .foregroundStyle(iconColor ?? .primary)
                    Text(title)
                }
                .font(.headline)

                Spacer()
                if let actionTitle, let action {
                    Button(actionTitle, action: action).font(.caption)
                }
            }
        }
    }
}
