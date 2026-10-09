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

final class VoicePromptManager {
    static let shared = VoicePromptManager()
    private let synth = AVSpeechSynthesizer()

    func speak(text: String, isJarvis: Bool = false) {
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        if isJarvis {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-GB") ?? AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = 0.48
            utterance.pitchMultiplier = 0.95
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "zh-TW") ?? AVSpeechSynthesisVoice(language: "zh-CN")
            utterance.rate = 0.50
        }
        synth.speak(utterance)
    }
}

/// Rogue App & Energy Vampire Detective.
