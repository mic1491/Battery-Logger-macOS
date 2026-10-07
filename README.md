# 🔋 Battery Logger for macOS

<p align="center">
  <img src="BatteryLoggerIcon.png" width="128" height="128" alt="Battery Logger Icon"/>
</p>

<p align="center">
  <b>The macOS battery companion that Apple didn't dare to build.</b><br>
  Hardware SMC charge limiting (80% / 85%), pure hardware power bypass, real-time wattage monitor, native frosted glass dashboard, Desktop Widgets, and zero-overhead performance.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2013%2B-blue?style=flat-square&logo=apple" alt="Platform"/>
  <img src="https://img.shields.io/badge/Architecture-Universal%202%20(Apple%20Silicon%20%2B%20Intel)-success?style=flat-square" alt="Architecture"/>
  <img src="https://img.shields.io/badge/Swift-5.9%2B-orange?style=flat-square&logo=swift" alt="Swift"/>
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License"/>
</p>

---

## ✨ Features / 核心特色

### 1. 🛡️ True Hardware Bypass (SMC BCLM Limiting)
- Unlike macOS's unpredictable "Optimized Battery Charging", Battery Logger writes directly to the Apple SMC `BCLM` register.
- Once your battery reaches 80% (or your custom threshold like 85%), charging physically cuts off (`0 mA`). Your Mac runs exclusively on wall power (Bypass), preserving battery lifespan and preventing cell swelling.

### 2. ⚡️ Real-Time Wattage & Diagnostics
- Monitor real-time charging power (`+28.4W`) and system discharge rate (`-11.2W`) with millisecond accuracy.
- Detect counterfeit chargers, slow USB-C cables, and energy-draining apps instantly.

### 3. 🔬 Raw Cell Health & Degradation Tracker
- Directly reads `AppleSmartBattery` register: exposes true Max Capacity (mAh) vs Design Capacity, cycle count, and cell voltage imbalance.
- Automatic milestone warnings when battery approaches 80% to help you claim AppleCare+ battery replacements in time.

### 4. 🍃 Automatic Low Power Mode
- When on battery and charge drops below 20%, automatically engages macOS Low Power Mode to grant up to ~1 extra hour of battery life. Automatically restores peak performance upon plugging in.

### 5. 🪟 Native Apple Frosted Glass Aesthetic
- Built using native SwiftUI and `NSVisualEffectView` (`.popover` material) with adaptive light/dark mode borders.
- No heavy Electron framework: pure Universal binary (2.8 MB) using ~0.0% CPU when idle.

### 6. 📱 Desktop Widgets & Interactive Pets
- **WidgetKit Integration**: Small, Medium, and Large desktop/notification center widgets featuring live 24-hour discharge charts.
- **Desktop Buddy**: Floating, draggable interactive reactor pet (Iron Man Arc Reactor, Captain America Shield, Cyber Core, and Pixel Monster).

---

## 🚀 Building from Source / 編譯方式

### Requirements
- macOS 13.0 or later (macOS 14+ recommended for Desktop Widgets)
- Xcode Command Line Tools (`xcode-select --install`)

### One-Click Build
Clone the repository and run:
```bash
git clone https://github.com/<YOUR_USERNAME>/Battery-Logger-macOS.git
cd Battery-Logger-macOS
./Build\ Battery\ Logger.command
```
The compiled universal `.app` will automatically be installed to `/Applications/Battery Logger.app` and launched.

---

## 📄 License
This project is licensed under the MIT License.
