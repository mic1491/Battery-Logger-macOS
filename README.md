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

---

## 📦 Quick Install / 快速下載安裝

### 方式一：直接下載發布版本（推薦）
1. 前往 [Releases 頁面](https://github.com/mic1491/Battery-Logger-macOS/releases/latest) 下載：
   - 📀 **`Battery_Logger_macOS_v2.0.0.dmg`**（推薦：Apple 原生磁碟映像檔，內建拖移捷徑與一鍵解除隔離工具）
   - 📦 **`Battery_Logger_macOS.zip`**（免掛載可攜式壓縮包）
2. 打開 DMG 將 `Battery Logger.app` 拖移至「應用程式」（`/Applications`）資料夾。
3. **⚠️ 解決 macOS「已損毀」或「無法打開」提示（Gatekeeper 隔離屬性）**：  
   由於本專案為個人開源軟體，未購買 Apple 年費開發者憑證。  
   - **DMG 使用者**：雙擊映像檔內的 **「一鍵解除 Gatekeeper 隔離」** 工具即可一秒解鎖！  
   - **或開啟終端機（Terminal）執行**：
     ```bash
     xattr -cr "/Applications/Battery Logger.app"
     ```

---

## 💻 Hardware Compatibility / 硬體相容性對照表

| 功能特色 | Intel Mac (2016–2020) | Apple Silicon (M1–M4) | 說明 |
| :--- | :---: | :---: | :--- |
| **即時充放電瓦數 (+W / -W)** | ✅ 支援 | ✅ 支援 | 原生 IOKit 即時電化學功率計算 |
| **電池健康度 (SOH) 與循環** | ✅ 支援 | ✅ 支援 | 讀取 `AppleSmartBattery` 真實容量 |
| **原生毛玻璃 UI & 儀表板** | ✅ 支援 | ✅ 支援 | 原生 SwiftUI + AppKit Popover |
| **macOS 桌面小組件 (Widgets)** | ✅ 支援 | ✅ 支援 | macOS 14+ WidgetKit 24 小時趨勢 |
| **休眠零洩漏保護 (Sleep Guard)** | ✅ 支援 | ✅ 支援 | 100% In-Memory C API，根除崩潰 |
| **低耗電模式自動切換 (LPM)** | ✅ 支援 | ✅ 支援 | 電量低於 20% 自動開啟，接電自動關閉 |
| **桌面動態精靈 (Desktop Buddy)** | ✅ 支援 | ✅ 支援 | 未接電源自動改為靜態光圈省電 |
| **80% 硬體限充 (SMC Bypass)** | ✅ 支援 (SMC `BCLM`) | ⚠️ 原生受限 | Apple Silicon 無 `BCLM` 暫存器，建議使用 macOS 原生最佳化充電 |
| **CPU 核心即時溫度** | ✅ 支援 (SMC `TC0P`) | ℹ️ 電池溫度支援 | Apple Silicon 採用統一記憶體架構與 HID 感測器 |

---

## 🚀 Building from Source / 從原始碼編譯

### 環境需求
- macOS 13.0 或更新版本（桌面小組件建議 macOS 14+）
- Xcode Command Line Tools（若無請於終端機執行 `xcode-select --install`）

### 一鍵編譯與安裝
複製本倉庫並執行編譯腳本：
```bash
git clone https://github.com/mic1491/Battery-Logger-macOS.git
cd Battery-Logger-macOS
./Build\ Battery\ Logger.command
```
腳本將自動編譯 Universal Binary（支援 x86_64 與 arm64 雙架構）並安裝至 `/Applications/Battery Logger.app`。

---

## 📄 License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
