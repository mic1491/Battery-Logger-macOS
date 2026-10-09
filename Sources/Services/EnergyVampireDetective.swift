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

enum EnergyVampireDetective {
    private static let lock = NSLock()
    private static var isScanning = false

    static func scanTopEnergyVampires() -> [EnergyVampireApp] {
        lock.lock()
        guard !isScanning else {
            lock.unlock()
            return []
        }
        isScanning = true
        lock.unlock()

        defer {
            lock.lock()
            isScanning = false
            lock.unlock()
        }

        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = ["-Ao", "pid,%cpu,comm", "-r"]
        let pipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = pipe
        task.standardError = errPipe

        defer {
            try? pipe.fileHandleForReading.close()
            try? pipe.fileHandleForWriting.close()
            try? errPipe.fileHandleForReading.close()
            try? errPipe.fileHandleForWriting.close()
        }

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            guard let output = String(data: data, encoding: .utf8) else { return [] }
            let lines = output.components(separatedBy: .newlines).dropFirst()
            var apps: [EnergyVampireApp] = []
            let ignoredNames = ["WindowServer", "launchd", "kernel_task", "BatteryLogger", "ps", "loginwindow", "logd"]

            for line in lines {
                let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", omittingEmptySubsequences: true)
                guard parts.count >= 3,
                      let pid = Int(parts[0]),
                      let cpu = Double(parts[1]) else { continue }
                if cpu < 5.0 { break }

                let rawPath = parts[2...].joined(separator: " ")
                let url = URL(fileURLWithPath: rawPath)
                let name = url.deletingPathExtension().lastPathComponent
                if ignoredNames.contains(where: { name.localizedCaseInsensitiveContains($0) }) {
                    continue
                }

                let friendlyName: String
                let bundleId: String?
                if let runningApp = NSRunningApplication(processIdentifier: pid_t(pid)) {
                    friendlyName = runningApp.localizedName ?? name
                    bundleId = runningApp.bundleIdentifier
                } else {
                    friendlyName = name
                    bundleId = nil
                }

                apps.append(EnergyVampireApp(id: pid, name: friendlyName, cpuPercent: cpu, bundleId: bundleId))
                if apps.count >= 3 { break }
            }
            return apps
        } catch {
            return []
        }
    }
}
