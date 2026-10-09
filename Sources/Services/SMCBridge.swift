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

@_silgen_name("BatteryLoggerReadCPUTemperature")
func BatteryLoggerReadCPUTemperature(_ value: UnsafeMutablePointer<Double>) -> Int32

@_silgen_name("BatteryLoggerReadChargeLimit")
func BatteryLoggerReadChargeLimit(_ value: UnsafeMutablePointer<Int32>) -> Int32
