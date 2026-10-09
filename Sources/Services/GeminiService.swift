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

/// Google Gemini AI integration service for battery diagnosis and interactive assistant.
@MainActor
final class GeminiService: ObservableObject {
    static let shared = GeminiService()

    @Published var isQuerying = false
    @Published var lastResponse: String?
    @Published var errorMessage: String?

    var apiKey: String {
        get { UserDefaults.standard.string(forKey: "geminiApiKey") ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "geminiApiKey") }
    }

    var selectedModel: String {
        get { UserDefaults.standard.string(forKey: "geminiSelectedModel") ?? "gemini-1.5-flash" }
        set { UserDefaults.standard.set(newValue, forKey: "geminiSelectedModel") }
    }

    var autoSpeakResponse: Bool {
        get { UserDefaults.standard.object(forKey: "geminiAutoSpeak") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "geminiAutoSpeak") }
    }

    func generateResponse(
        prompt: String,
        snapshot: BatterySnapshot,
        skin: BuddySkin,
        topVampires: [EnergyVampireApp],
        limit: Int?
    ) async -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            return "長官，尚未設定 Gemini API Key。請點擊「偏好設定」>「Google Gemini AI」輸入您的 API Key 即可啟動大腦！"
        }

        isQuerying = true
        errorMessage = nil

        let isIronMan = skin == .arcReactor
        let systemPrompt = """
        You are an advanced AI battery engineer and personal companion inside a Mac system.
        Persona: \(isIronMan ? "You are J.A.R.V.I.S., Tony Stark's sophisticated AI butler. Respond in witty, concise, highly professional British butler style. You may speak in Traditional Chinese or English when appropriate." : "You are a friendly, scientifically knowledgeable Mac battery guardian and energy advisor. Speak in warm, polite Traditional Chinese.")

        Current Real-time Mac Hardware Telemetry:
        • Device: \(snapshot.model) (\(snapshot.processor), \(snapshot.memory))
        • macOS: \(snapshot.macOS)
        • Battery Level: \(snapshot.percent.map { "\($0)%" } ?? "Unknown")
        • Power State: \(snapshot.externalPower == true ? "Connected to AC Charger" : "Discharging on Battery")
        • Charging Status: \(snapshot.powerStatusText)
        • Voltage: \(snapshot.voltage.map { "\(Double($0)/1000.0)V" } ?? "Unknown")
        • Wattage: \(snapshot.charging == true ? (snapshot.chargeWatts.map { "+\(String(format: "%.1f", $0))W" } ?? "0W") : (snapshot.dischargeWatts.map { "-\(String(format: "%.1f", $0))W" } ?? "0W"))
        • Temperature: \(snapshot.temperature.map { String(format: "%.1f°C", $0) } ?? "Unknown")
        • Battery Health (SOH): \(snapshot.healthPercent.map { String(format: "%.1f%%", $0) } ?? "Unknown")
        • Cycles: \(snapshot.cycles.map { "\($0) cycles" } ?? "Unknown")
        • Cell Imbalance: \(snapshot.cellBalanceText)
        • Hardware Charge Limit: \(limit.map { "\($0)%" } ?? "100%")
        • Active Top Energy Apps: \(topVampires.map { "\($0.name) (\(String(format: "%.0f", $0.cpuPercent))% CPU)" }.joined(separator: ", "))

        Instructions:
        1. Keep responses concise (under 120 words unless requested detailed report), direct, and actionable.
        2. Incorporate real battery electrochemistry (e.g. 30%-80% shallow charge cycles, avoidance of 4.3V high voltage stress, thermal safeguards).
        3. Maintain persona perfectly!
        """

        let model = selectedModel.isEmpty ? "gemini-1.5-flash" : selectedModel
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(key)") else {
            isQuerying = false
            return "API 網址格式錯誤。"
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": "\(systemPrompt)\n\nUser Question / Command: \(prompt)"]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 600
            ]
        ]

        guard let httpData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            isQuerying = false
            return "無法序列化請求資料。"
        }
        request.httpBody = httpData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            isQuerying = false

            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode != 200 {
                let errText = String(data: data, encoding: .utf8) ?? "未知錯誤"
                return "Gemini API 呼叫失敗 (\(httpResp.statusCode))：\(errText.prefix(100))"
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let firstCandidate = candidates.first,
                  let content = firstCandidate["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let firstPart = parts.first,
                  let text = firstPart["text"] as? String else {
                return "無法解析 Gemini 回應內容。"
            }

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            self.lastResponse = trimmed

            if autoSpeakResponse {
                VoicePromptManager.shared.speak(text: trimmed, isJarvis: isIronMan)
            }

            return trimmed
        } catch {
            isQuerying = false
            self.errorMessage = error.localizedDescription
            return "連線失敗：\(error.localizedDescription)"
        }
    }
}
