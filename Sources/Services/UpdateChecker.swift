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

// MARK: - GitHub Auto Update Checker
struct GitHubReleaseInfo: Decodable {
    let tagName: String
    let htmlUrl: String
    let name: String?
    let body: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case name
        case body
    }
}

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published var latestVersion: String? = nil
    @Published var releaseURL: URL? = nil
    @Published var hasUpdate: Bool = false
    @Published var isChecking: Bool = false
    @Published var statusMessage: String? = nil

    let currentVersion = "v2.0.0"

    func checkForUpdates(silent: Bool = true) {
        guard !isChecking else { return }
        isChecking = true
        if !silent { statusMessage = "正在連線 GitHub 檢查更新…" }

        guard let url = URL(string: "https://api.github.com/repos/mic1491/Battery-Logger-macOS/releases/latest") else {
            isChecking = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 8.0

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            Task { @MainActor in
                guard let self = self else { return }
                self.isChecking = false
                guard let data = data, error == nil,
                      let release = try? JSONDecoder().decode(GitHubReleaseInfo.self, from: data) else {
                    if !silent { self.statusMessage = "暫時無法取得 GitHub 更新資訊" }
                    return
                }

                let remoteTag = release.tagName.trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanRemote = remoteTag.replacingOccurrences(of: "v", with: "")
                let cleanCurrent = self.currentVersion.replacingOccurrences(of: "v", with: "")

                if cleanRemote.compare(cleanCurrent, options: .numeric) == .orderedDescending {
                    self.latestVersion = remoteTag
                    self.releaseURL = URL(string: release.htmlUrl)
                    self.hasUpdate = true
                    if !silent { self.statusMessage = "發現新版本 \(remoteTag)！" }
                } else {
                    self.hasUpdate = false
                    if !silent { self.statusMessage = "已是最新版本 (\(self.currentVersion))" }
                }
            }
        }.resume()
    }
}
