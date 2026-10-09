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

/// An NSImage subclass that overrides `isTemplate` so SwiftUI's MenuBarExtra cannot force it into monochrome template mode.
final class NonTemplateImage: NSImage {
    override var isTemplate: Bool {
        get { false }
        set { /* No-op: Prevent SwiftUI from converting to monochrome template */ }
    }
}

/// Renders a non-template NSImage so macOS MenuBarExtra displays vivid real colors.
@MainActor
enum MenuBarIconRenderer {
    static func render(snapshot: BatterySnapshot, isCharging: Bool, isDischarging: Bool, isFullyCharged: Bool, isDark: Bool, mode: MenuBarDisplayMode = .iconAndPercent) -> NSImage {
        let pct = snapshot.percent ?? 0
        let temp = snapshot.temperature ?? 25.0

        // Multi-tier color hierarchy for high visibility and clear recognition:
        let color: NSColor
        if temp >= 36.5 {
            color = NSColor(srgbRed: 0.95, green: 0.23, blue: 0.23, alpha: 1.0)
        } else if isCharging {
            color = NSColor(srgbRed: 0.18, green: 0.82, blue: 0.35, alpha: 1.0)
        } else {
            if pct >= 85 {
                color = NSColor(srgbRed: 0.18, green: 0.82, blue: 0.35, alpha: 1.0)
            } else if pct >= 60 {
                color = NSColor(srgbRed: 0.0, green: 0.68, blue: 0.95, alpha: 1.0)
            } else if pct >= 35 {
                color = NSColor(srgbRed: 0.98, green: 0.72, blue: 0.05, alpha: 1.0)
            } else if pct >= 21 {
                color = NSColor(srgbRed: 1.0, green: 0.55, blue: 0.08, alpha: 1.0)
            } else {
                color = NSColor(srgbRed: 0.95, green: 0.23, blue: 0.23, alpha: 1.0)
            }
        }

        let isDarkMode = isDark
        // Native solid menu bar text: Pure solid white in dark mode, pure solid black in light mode
        let textSolidColor: NSColor = isDarkMode ? .white : .black
        // Battery capsule frame dynamically follows macOS native styling
        let frameStrokeColor: NSColor = textSolidColor.withAlphaComponent(isDarkMode ? 0.48 : 0.38)

        let textStr: String
        if mode == .iconAndRemainingTime {
            if let time = snapshot.timeRemaining, time > 0, time < 1440 {
                textStr = "\(time / 60):\(String(format: "%02d", time % 60))"
            } else {
                textStr = snapshot.percent.map { "\($0)%" } ?? "—%"
            }
        } else {
            textStr = snapshot.percent.map { "\($0)%" } ?? "—%"
        }

        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textSolidColor
        ]
        let attrStr = NSAttributedString(string: textStr, attributes: textAttrs)
        let textSize = attrStr.size()
        let batteryWidth: CGFloat = 29
        let spacing: CGFloat = 4
        let totalHeight: CGFloat = 22

        let totalWidth: CGFloat
        switch mode {
        case .iconOnly:
            totalWidth = batteryWidth + 2
        case .percentOnly:
            totalWidth = ceil(textSize.width) + 4
        case .iconAndPercent, .iconAndRemainingTime:
            totalWidth = ceil(batteryWidth + spacing + textSize.width + 4)
        }

        let symbolName: String? = isCharging ? "bolt.fill" : (!isDischarging ? "powerplug.fill" : nil)
        let symbol = symbolName.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
                .applying(.init(paletteColors: [textSolidColor])))

        let image = NonTemplateImage(size: NSSize(width: totalWidth, height: totalHeight), flipped: false) { _ in
            let shouldDrawBattery = mode != .percentOnly
            let shouldDrawText = mode != .iconOnly

            if shouldDrawBattery {
                let body = NSRect(x: 1.5, y: 4.5, width: 26, height: 13)
                let frame = NSBezierPath(roundedRect: body, xRadius: 2.8, yRadius: 2.8)
                frame.lineWidth = 0.85
                frameStrokeColor.setStroke()
                frame.stroke()

                // A short rounded terminal, matching the body outline weight.
                let terminal = NSBezierPath()
                terminal.move(to: NSPoint(x: body.maxX + 1.2, y: 8.8))
                terminal.curve(to: NSPoint(x: body.maxX + 1.2, y: 13.2),
                               controlPoint1: NSPoint(x: body.maxX + 2.3, y: 8.8),
                               controlPoint2: NSPoint(x: body.maxX + 2.3, y: 13.2))
                terminal.lineWidth = 0.85
                terminal.lineCapStyle = .round
                frameStrokeColor.setStroke()
                terminal.stroke()

                let interior = body.insetBy(dx: 1.7, dy: 1.7)
                let fillWidth = interior.width * CGFloat(max(0, min(100, pct))) / 100
                if fillWidth > 0 {
                    NSGraphicsContext.saveGraphicsState()
                    NSBezierPath(roundedRect: interior, xRadius: 1.2, yRadius: 1.2).addClip()
                    color.setFill()
                    NSRect(x: interior.minX, y: interior.minY, width: fillWidth, height: interior.height).fill()
                    NSGraphicsContext.restoreGraphicsState()
                }
                if let symbol {
                    let size = symbol.size
                    symbol.draw(in: NSRect(x: body.midX - size.width / 2,
                                           y: body.midY - size.height / 2,
                                           width: size.width, height: size.height))
                }
            }

            if shouldDrawText {
                let textX: CGFloat = (mode == .percentOnly) ? 2 : (batteryWidth + spacing + 1)
                attrStr.draw(in: NSRect(x: textX,
                                       y: round((totalHeight - textSize.height) / 2),
                                       width: ceil(textSize.width) + 1, height: ceil(textSize.height)))
            }
            return true
        }

        image.isTemplate = false
        return image
    }
}
