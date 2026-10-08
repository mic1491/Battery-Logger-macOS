#!/bin/zsh
set -e
BUILD_SCRIPT="${0:A}"
cd "$(dirname "$0")"
if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "此 Mac 尚未安裝 Xcode Command Line Tools，無法編譯原生 App。"
  echo "請先在 Terminal 執行：xcode-select --install"
  read -r "?按 Enter 結束。"
  exit 1
fi
APP="$(pwd)/Battery Logger.app"
BUILD_CACHE="${TMPDIR:-/private/tmp}/battery-logger-module-cache"
mkdir -p "$BUILD_CACHE/x86_64/modules" "$BUILD_CACHE/arm64/modules"
xcrun clang -O2 -arch x86_64 -mmacosx-version-min=13.0 -c "SMCTemperature.c" -o "$BUILD_CACHE/x86_64/SMCTemperature.o"
xcrun clang -O2 -arch arm64 -mmacosx-version-min=13.0 -c "SMCTemperature.c" -o "$BUILD_CACHE/arm64/SMCTemperature.o"
xcrun clang -O2 -arch x86_64 -mmacosx-version-min=13.0 -framework IOKit "smc_battery_tool.c" -o "$BUILD_CACHE/x86_64/smc-battery-tool"
xcrun clang -O2 -arch arm64 -mmacosx-version-min=13.0 -framework IOKit "smc_battery_tool.c" -o "$BUILD_CACHE/arm64/smc-battery-tool"
lipo -create "$BUILD_CACHE/x86_64/smc-battery-tool" "$BUILD_CACHE/arm64/smc-battery-tool" -output "$BUILD_CACHE/smc-battery-tool"
if [[ ! -x "$BUILD_CACHE/BatteryLogger-x86_64" || ! -x "$BUILD_CACHE/BatteryLogger-arm64" || "BatteryLoggerApp.swift" -nt "$BUILD_CACHE/BatteryLogger-x86_64" || "BatteryLoggerApp.swift" -nt "$BUILD_CACHE/BatteryLogger-arm64" || "SMCTemperature.c" -nt "$BUILD_CACHE/BatteryLogger-x86_64" || "SMCTemperature.c" -nt "$BUILD_CACHE/BatteryLogger-arm64" ]]; then
  xcrun swiftc -parse-as-library -Onone -module-cache-path "$BUILD_CACHE/x86_64" -target x86_64-apple-macosx13.0 -framework SwiftUI -framework AppKit -framework ServiceManagement -framework IOKit -framework Carbon -framework WidgetKit -framework UserNotifications -framework AVFoundation -framework EventKit "BatteryLoggerApp.swift" "$BUILD_CACHE/x86_64/SMCTemperature.o" -o "$BUILD_CACHE/BatteryLogger-x86_64"
  xcrun swiftc -parse-as-library -Onone -module-cache-path "$BUILD_CACHE/arm64" -target arm64-apple-macosx13.0 -framework SwiftUI -framework AppKit -framework ServiceManagement -framework IOKit -framework Carbon -framework WidgetKit -framework UserNotifications -framework AVFoundation -framework EventKit "BatteryLoggerApp.swift" "$BUILD_CACHE/arm64/SMCTemperature.o" -o "$BUILD_CACHE/BatteryLogger-arm64"
fi
lipo -create "$BUILD_CACHE/BatteryLogger-x86_64" "$BUILD_CACHE/BatteryLogger-arm64" -output "$BUILD_CACHE/BatteryLogger"
# A macOS WidgetKit extension must enter through NSExtensionMain; the Swift main
# returns before serving descriptors when used as the process entry point.
if [[ ! -x "$BUILD_CACHE/BatteryLoggerWidget-x86_64" || ! -x "$BUILD_CACHE/BatteryLoggerWidget-arm64" || "BatteryLoggerWidget.swift" -nt "$BUILD_CACHE/BatteryLoggerWidget-x86_64" || "BatteryLoggerWidget.swift" -nt "$BUILD_CACHE/BatteryLoggerWidget-arm64" || "$BUILD_SCRIPT" -nt "$BUILD_CACHE/BatteryLoggerWidget-x86_64" || "$BUILD_SCRIPT" -nt "$BUILD_CACHE/BatteryLoggerWidget-arm64" ]]; then
  xcrun swiftc -parse-as-library -application-extension -Xlinker -e -Xlinker _NSExtensionMain -Onone -module-cache-path "$BUILD_CACHE/x86_64" -target x86_64-apple-macosx14.0 -framework SwiftUI -framework WidgetKit -framework Charts -framework IOKit "BatteryLoggerWidget.swift" -o "$BUILD_CACHE/BatteryLoggerWidget-x86_64"
  xcrun swiftc -parse-as-library -application-extension -Xlinker -e -Xlinker _NSExtensionMain -Onone -module-cache-path "$BUILD_CACHE/arm64" -target arm64-apple-macosx14.0 -framework SwiftUI -framework WidgetKit -framework Charts -framework IOKit "BatteryLoggerWidget.swift" -o "$BUILD_CACHE/BatteryLoggerWidget-arm64"
fi
lipo -create "$BUILD_CACHE/BatteryLoggerWidget-x86_64" "$BUILD_CACHE/BatteryLoggerWidget-arm64" -output "$BUILD_CACHE/BatteryLoggerWidget"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_CACHE/BatteryLogger" "$APP/Contents/MacOS/BatteryLogger"
chmod +x "$APP/Contents/MacOS/BatteryLogger"
cp "$BUILD_CACHE/smc-battery-tool" "$APP/Contents/Resources/smc-battery-tool"
chmod +x "$APP/Contents/Resources/smc-battery-tool"
cp "BatteryLoggerIcon.icns" "$APP/Contents/Resources/applet.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>BatteryLogger</string>
<key>CFBundleIdentifier</key><string>local.codex.batterylogger.v2</string>
<key>CFBundleName</key><string>Battery Logger</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
<key>CFBundleShortVersionString</key><string>2.0.0</string>
<key>CFBundleVersion</key><string>50</string>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 Matt. All rights reserved.</string>
<key>CFBundleIconFile</key><string>applet</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppleEventsUsageDescription</key><string>電池記錄器需要透過「訊息」發送充電完成的 iMessage 通知至您的 iPhone。</string>
<key>NSCalendarsUsageDescription</key><string>電池記錄器需要讀取行事曆外出行程，以便在您出門前提前建議充飽電。</string>
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key><string>local.codex.batterylogger</string>
    <key>CFBundleURLSchemes</key><array><string>batterylogger</string></array>
  </dict>
</array>
</dict></plist>
PLIST
WIDGET="$APP/Contents/PlugIns/BatteryLoggerWidget.appex"
mkdir -p "$WIDGET/Contents/MacOS"
cp "$BUILD_CACHE/BatteryLoggerWidget" "$WIDGET/Contents/MacOS/BatteryLoggerWidget"
chmod +x "$WIDGET/Contents/MacOS/BatteryLoggerWidget"
cat > "$WIDGET/Contents/Info.plist" <<'WIDGET_PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>BatteryLoggerWidget</string>
<key>CFBundleIdentifier</key><string>local.codex.batterylogger.v2.widget</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleName</key><string>Battery Logger Widget</string>
<key>CFBundlePackageType</key><string>XPC!</string>
<key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
<key>CFBundleShortVersionString</key><string>2.0.0</string>
<key>CFBundleVersion</key><string>50</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSExtension</key><dict>
<key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string>
</dict>
</dict></plist>
WIDGET_PLIST
WIDGET_ENTITLEMENTS="$BUILD_CACHE/BatteryLoggerWidget.entitlements"
cat > "$WIDGET_ENTITLEMENTS" <<'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.security.app-sandbox</key><true/>
</dict></plist>
ENTITLEMENTS
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --sign - --entitlements "$WIDGET_ENTITLEMENTS" "$WIDGET"
codesign --force --sign - "$APP/Contents/Resources/smc-battery-tool"
codesign --force --sign - "$APP/Contents/MacOS/BatteryLogger"
codesign --force --sign - "$APP"
echo "已建立 Battery Logger.app。"
if [ -d "/Applications" ]; then
  STAGING="/Applications/.Battery Logger.app.new.$$"
  rm -rf "$STAGING"
  ditto "$APP" "$STAGING"
  codesign --verify --deep --strict "$STAGING"
  pkill -9 -f "Battery Logger.app/Contents/MacOS/applet" 2>/dev/null || true
  pkill -9 -f "Battery Logger.app/Contents/MacOS/BatteryLogger" 2>/dev/null || true
  sleep 0.8
  rm -rf "/Applications/Battery Logger.app"
  mv "$STAGING" "/Applications/Battery Logger.app"
  echo "已同步更新至 /Applications/Battery Logger.app。"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/Battery Logger.app"
  /usr/bin/pluginkit -r "$WIDGET" || true
  /usr/bin/pluginkit -a "/Applications/Battery Logger.app/Contents/PlugIns/BatteryLoggerWidget.appex"
  /usr/bin/pluginkit -e use -p com.apple.widgetkit-extension -i local.codex.batterylogger.v2.widget
  open "/Applications/Battery Logger.app"
else
  open "$APP"
fi
