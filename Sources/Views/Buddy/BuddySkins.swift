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

// MARK: - 1. Classic Glassy Aurora Orb Skin
struct ClassicSkinView: View {
    let isCharging: Bool
    let percent: Int?
    let emoji: String
    let moodColor: Color
    @Environment(\.colorScheme) private var colorScheme
    @State private var isBreathing = false

    var body: some View {
        ZStack {
            // Outer aura ring (Breathes gently in standby, rapid pulse when charging)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            moodColor.opacity(isBreathing ? (isCharging ? 0.65 : 0.40) : 0.18),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(
                    width: isBreathing ? (isCharging ? 74 : 69) : 63,
                    height: isBreathing ? (isCharging ? 74 : 69) : 63
                )

            // Inner glass circle
            Circle()
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.85))
                .frame(width: 56, height: 56)
                .shadow(
                    color: moodColor.opacity(isBreathing ? (isCharging ? 0.60 : 0.45) : 0.20),
                    radius: isBreathing ? (isCharging ? 10 : 8) : 4,
                    x: 0,
                    y: 3
                )
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    colorScheme == .dark ? Color.white.opacity(0.55) : Color.white.opacity(0.90),
                                    colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.14)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.75
                        )
                )

            // Character Emoji
            Text(emoji)
                .font(.system(size: 28))

            // Lightning or Sparkle Badge
            Image(systemName: isCharging ? "bolt.fill" : "sparkles")
                .font(.system(size: isCharging ? 11 : 13, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: isCharging ? [.yellow, .green] : [.purple, moodColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .scaleEffect(isBreathing ? (isCharging ? 1.25 : 1.05) : 0.95)
                .shadow(color: isCharging ? Color.green.opacity(isBreathing ? 0.8 : 0.3) : .clear, radius: isBreathing ? 5 : 1)
                .offset(x: 20, y: -20)

            // Battery percentage pill on the bottom
            Text(percent.map { "\($0)%" } ?? "—%")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(moodColor, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.35 : 0.6), lineWidth: 0.5)
                )
                .offset(y: 24)
        }
        .onAppear {
            startBreathing()
        }
        .onChange(of: isCharging) { _ in
            startBreathing()
        }
    }

    private func startBreathing() {
        isBreathing = false
        // Power saving: infinite 60fps animations only while charging; static glow otherwise.
        guard isCharging else {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { isBreathing = true }
            return
        }
        DispatchQueue.main.async {
            withAnimation(Animation.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
    }
}

// MARK: - 2. Retro 8-bit Pixel Battery Monster Skin
struct PixelMonsterSkinView: View {
    let isCharging: Bool
    let isDizzy: Bool
    let percent: Int?
    @State private var isBreathing = false

    var body: some View {
        ZStack {
            // Retro CRT screen outer bezel
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.88))
                .frame(width: 60, height: 60)
                .shadow(color: Color.green.opacity(isBreathing ? (isCharging ? 0.80 : 0.50) : 0.20), radius: isBreathing ? (isCharging ? 10 : 6) : 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(isCharging ? Color.green : Color.green.opacity(isBreathing ? 0.8 : 0.4), lineWidth: 1.5)
                )

            VStack(spacing: 2) {
                // Pixel Monster Face
                Text(isDizzy ? "😵" : (isCharging ? "👾" : "👾"))
                    .font(.system(size: 24))
                    .scaleEffect(isBreathing ? 1.06 : 0.95)

                // 8-bit Heart Health Bar
                Text(percent.map { "\($0)%" } ?? "—%")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundStyle(isCharging ? Color.green : Color.cyan)
            }

            // Top-right pixel status indicator
            Circle()
                .fill(isCharging ? Color.yellow : Color.green)
                .frame(width: 6, height: 6)
                .shadow(color: isCharging ? .yellow : .green, radius: isBreathing ? 4 : 1)
                .offset(x: 22, y: -22)
        }
        .onAppear {
            startBreathing()
        }
        .onChange(of: isCharging) { _ in
            startBreathing()
        }
    }

    private func startBreathing() {
        isBreathing = false
        // Power saving: infinite 60fps animations only while charging; static glow otherwise.
        guard isCharging else {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { isBreathing = true }
            return
        }
        DispatchQueue.main.async {
            withAnimation(Animation.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
    }
}

// MARK: - 3. Cyberpunk Techno Core Skin
struct CyberCoreSkinView: View {
    let isCharging: Bool
    let isDizzy: Bool
    let percent: Int?
    @State private var isBreathing = false
    @State private var isRotating = false

    var body: some View {
        ZStack {
            // Rotating Outer Techno Ring
            Circle()
                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(LinearGradient(colors: [.cyan, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 62, height: 62)
                .rotationEffect(.degrees(isRotating ? 360 : 0))

            // Inner Core Arc Reactor
            Circle()
                .fill(RadialGradient(colors: [Color.cyan.opacity(isBreathing ? 0.50 : 0.20), Color.black.opacity(0.85)], center: .center, startRadius: 2, endRadius: 28))
                .frame(width: 52, height: 52)
                .shadow(color: .cyan.opacity(isBreathing ? (isCharging ? 0.85 : 0.55) : 0.25), radius: isBreathing ? (isCharging ? 10 : 6) : 3)

            // High-tech Arc Symbol
            Text(isDizzy ? "🌀" : (isCharging ? "⚛️" : "💠"))
                .font(.system(size: 24))
                .scaleEffect(isBreathing ? 1.08 : 0.95)

            // Bottom Cyber HUD readout
            Text(percent.map { "\($0)%" } ?? "—%")
                .font(.system(size: 8.5, weight: .black, design: .monospaced))
                .foregroundStyle(.cyan)
                .padding(.horizontal, 4)
                .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 3))
                .offset(y: 22)
        }
        .onAppear {
            startBreathing()
        }
        .onChange(of: isCharging) { _ in
            startBreathing()
        }
    }

    private func startBreathing() {
        isBreathing = false
        // Power saving: infinite 60fps animations only while charging; static glow otherwise.
        guard isCharging else {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { isBreathing = true }
            return
        }
        DispatchQueue.main.async {
            withAnimation(Animation.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
            withAnimation(Animation.linear(duration: 4.0).repeatForever(autoreverses: false)) {
                isRotating = true
            }
        }
    }
}

// MARK: - 4. Iron Man Arc Reactor Skin (鋼鐵人方舟反應爐脈衝呼吸燈)
struct ArcReactorSkinView: View {
    let isCharging: Bool
    let percent: Int?
    @State private var isBreathing = false

    var body: some View {
        ZStack {
            // 1. High-energy Unibeam aura & Standby Breathing Plasma Halo
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.12, green: 0.85, blue: 1.0).opacity(isBreathing ? (isCharging ? 0.85 : 0.45) : (isCharging ? 0.35 : 0.12)),
                            Color.cyan.opacity(isBreathing ? (isCharging ? 0.45 : 0.22) : 0.05),
                            .clear
                        ],
                        center: .center,
                        startRadius: 16,
                        endRadius: 38
                    )
                )
                .frame(
                    width: isBreathing ? (isCharging ? 76 : 70) : (isCharging ? 66 : 62),
                    height: isBreathing ? (isCharging ? 76 : 70) : (isCharging ? 66 : 62)
                )

            // 2. Heavy Titanium / Gold Alloy Housing
            Circle()
                .fill(Color(red: 0.07, green: 0.09, blue: 0.13))
                .frame(width: 58, height: 58)
                .shadow(
                    color: Color.cyan.opacity(isBreathing ? (isCharging ? 0.90 : 0.65) : 0.25),
                    radius: isBreathing ? (isCharging ? 10 : 6) : 2.5
                )
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.88, green: 0.68, blue: 0.28),
                                    Color(red: 0.32, green: 0.37, blue: 0.44)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )

            // 3. 10 Segmented Magnetic Confinement Coils around perimeter
            ForEach(0..<10) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.96, green: 0.62, blue: 0.25),
                                Color(red: 0.65, green: 0.35, blue: 0.15)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3.5, height: 6.5)
                    .offset(y: -23)
                    .rotationEffect(.degrees(Double(i) * 36.0 + (isCharging && isBreathing ? 3.0 : 0.0)))
            }

            // 4. 10 Inter-coil Cyan Plasma Micro-Discharge Nodes (Breathing Spark Gaps)
            ForEach(0..<10) { i in
                Circle()
                    .fill(Color.cyan)
                    .frame(width: 2.2, height: 2.2)
                    .shadow(
                        color: .cyan,
                        radius: isBreathing ? (isCharging ? 3 : 2) : 0.5
                    )
                    .opacity(isBreathing ? (isCharging ? 1.0 : 0.90) : 0.20)
                    .offset(y: -23)
                    .rotationEffect(.degrees(Double(i) * 36.0 + 18.0))
            }

            // 5. Glowing Cyan Energy Laser Arc Ring
            Circle()
                .stroke(
                    Color.cyan.opacity(isBreathing ? (isCharging ? 1.0 : 0.95) : 0.45),
                    lineWidth: isBreathing ? (isCharging ? 2.2 : 1.8) : 1.2
                )
                .frame(width: 36, height: 36)
                .shadow(
                    color: .cyan.opacity(isBreathing ? (isCharging ? 0.95 : 0.85) : 0.25),
                    radius: isBreathing ? (isCharging ? 8 : 5) : 2
                )

            // 6. Center Palladium / Vibranium Triangular Core with Unibeam lens
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white,
                                Color(red: 0.10, green: 0.85, blue: 1.0),
                                Color(red: 0.02, green: 0.40, blue: 0.80)
                            ],
                            center: .center,
                            startRadius: 1,
                            endRadius: 12
                        )
                    )
                    .frame(width: 22, height: 22)
                    .scaleEffect(isBreathing ? (isCharging ? 1.15 : 1.06) : 0.94)
                    .shadow(
                        color: Color.cyan,
                        radius: isBreathing ? (isCharging ? 12 : 7) : 2.5
                    )

                Image(systemName: "triangle.fill")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(Color(red: 0.06, green: 0.10, blue: 0.15))
                    .rotationEffect(.degrees(180))

                Circle()
                    .fill(Color.white)
                    .frame(width: 4.5, height: 4.5)
                    .scaleEffect(isBreathing ? (isCharging ? 1.4 : 1.25) : 0.8)
                    .shadow(
                        color: .white,
                        radius: isBreathing ? (isCharging ? 4 : 3) : 1
                    )
            }

            // 7. Bottom Mark / Arc HUD Readout
            Text(percent.map { "ARC \($0)%" } ?? "ARC —%")
                .font(.system(size: 7.5, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color.cyan)
                .padding(.horizontal, 4)
                .padding(.vertical, 0.5)
                .background(Color.black.opacity(0.85), in: Capsule())
                .overlay(
                    Capsule().strokeBorder(Color.cyan.opacity(isBreathing ? 0.85 : 0.35), lineWidth: 0.5)
                )
                .offset(y: 24)
        }
        .onAppear {
            startBreathing()
        }
        .onChange(of: isCharging) { _ in
            startBreathing()
        }
    }

    private func startBreathing() {
        isBreathing = false
        // Power saving: infinite 60fps animations only while charging; static glow otherwise.
        guard isCharging else {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { isBreathing = true }
            return
        }
        DispatchQueue.main.async {
            withAnimation(Animation.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
    }
}

// MARK: - 5. Captain America Vibranium Energy Shield Skin
struct CaptainShieldSkinView: View {
    let isCharging: Bool
    let percent: Int?
    @State private var isBreathing = false

    var body: some View {
        ZStack {
            // Kinetic energy pulse aura when charging (汎合金能量擴散環)
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color.red, Color.blue, Color.white],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isCharging ? (isBreathing ? 2.5 : 1.0) : (isBreathing ? 1.2 : 0.4)
                )
                .frame(
                    width: isBreathing ? (isCharging ? 76 : 68) : (isCharging ? 64 : 62),
                    height: isBreathing ? (isCharging ? 76 : 68) : (isCharging ? 64 : 62)
                )
                .opacity(isBreathing ? (isCharging ? 0.85 : 0.35) : (isCharging ? 0.25 : 0.10))

            // Outer Crimson Red Vibranium Ring
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.92, green: 0.15, blue: 0.18),
                            Color(red: 0.65, green: 0.08, blue: 0.10)
                        ],
                        center: .center,
                        startRadius: 24,
                        endRadius: 30
                    )
                )
                .frame(width: 60, height: 60)
                .shadow(
                    color: Color.red.opacity(isBreathing ? (isCharging ? 0.70 : 0.45) : 0.20),
                    radius: isBreathing ? (isCharging ? 8 : 5) : 2.5
                )

            // Silver White Titanium Ring
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.95, green: 0.96, blue: 0.98),
                            Color(red: 0.78, green: 0.80, blue: 0.84)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 48, height: 48)

            // Middle Crimson Red Ring
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.92, green: 0.15, blue: 0.18),
                            Color(red: 0.65, green: 0.08, blue: 0.10)
                        ],
                        center: .center,
                        startRadius: 14,
                        endRadius: 20
                    )
                )
                .frame(width: 36, height: 36)

            // Deep Cobalt Blue Center Circle
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.12, green: 0.38, blue: 0.82),
                            Color(red: 0.05, green: 0.18, blue: 0.48)
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: 12
                    )
                )
                .frame(width: 24, height: 24)

            // Gleaming Silver Vibranium Star
            Image(systemName: "star.fill")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, Color(red: 0.82, green: 0.85, blue: 0.90)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .scaleEffect(isBreathing ? (isCharging ? 1.15 : 1.05) : 0.95)
                .shadow(color: .white.opacity(isBreathing ? (isCharging ? 0.9 : 0.6) : 0.25), radius: isBreathing ? 4 : 1.5)

            // Diagonal Metallic Specular Highlight
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.35), Color.clear, Color.black.opacity(0.25)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 60, height: 60)
                .allowsHitTesting(false)

            // Bottom Shield HUD Pill
            Text(percent.map { "CAP \($0)%" } ?? "CAP —%")
                .font(.system(size: 7.5, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 0.5)
                .background(Color(red: 0.08, green: 0.18, blue: 0.45).opacity(0.9), in: Capsule())
                .overlay(
                    Capsule().strokeBorder(Color.red.opacity(isBreathing ? 0.85 : 0.45), lineWidth: 0.5)
                )
                .offset(y: 24)
        }
        .onAppear {
            startBreathing()
        }
        .onChange(of: isCharging) { _ in
            startBreathing()
        }
    }

    private func startBreathing() {
        isBreathing = false
        // Power saving: infinite 60fps animations only while charging; static glow otherwise.
        guard isCharging else {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { isBreathing = true }
            return
        }
        DispatchQueue.main.async {
            withAnimation(Animation.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
    }
}
