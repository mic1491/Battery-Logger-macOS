#!/bin/zsh
set -e

cd "$(dirname "$0")"

APP="Battery Logger.app"
if [ ! -d "$APP" ]; then
    if [ -d "/Applications/Battery Logger.app" ]; then
        APP="/Applications/Battery Logger.app"
    else
        echo "找不到 Battery Logger.app，請先執行 ./Build\\ Battery\\ Logger.command"
        exit 1
    fi
fi

DMG_NAME="Battery_Logger_macOS_v2.0.0.dmg"
STAGING_DIR="/tmp/battery_logger_dmg_staging_$$"

echo "正在準備 DMG 映像檔打包內容..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

# 1. 複製 App
cp -R "$APP" "$STAGING_DIR/Battery Logger.app"

# 2. 建立 Applications 捷徑
ln -s /Applications "$STAGING_DIR/Applications"

# 3. 建立一鍵解除 Gatekeeper 工具
cat > "$STAGING_DIR/一鍵解除 Gatekeeper 隔離 (無法打開時執行).command" << 'EOF'
#!/bin/zsh
echo "=========================================================="
echo "  Battery Logger macOS 一鍵解除 Gatekeeper 隔離屬性"
echo "=========================================================="
echo "此工具將為 /Applications/Battery Logger.app 解除 macOS 隔離屬性。"
echo ""
xattr -cr "/Applications/Battery Logger.app" 2>/dev/null || sudo xattr -cr "/Applications/Battery Logger.app" 2>/dev/null || true
echo "✅ 解除完成！現在您可以直接從「應用程式」點擊開啟 Battery Logger。"
echo "按任意鍵關閉此視窗。"
read -k 1 -s
EOF
chmod +x "$STAGING_DIR/一鍵解除 Gatekeeper 隔離 (無法打開時執行).command"

# 4. 建立說明文字
cat > "$STAGING_DIR/安裝說明.txt" << 'EOF'
🔋 Battery Logger for macOS v2.0.0

【安裝步驟】
1. 將「Battery Logger.app」拖移至「Applications」資料夾。
2. 開啟 Launchpad 或「應用程式」啟動 Battery Logger。

【若系統提示「已損毀」或「無法打開」】
由於本專案為開源軟體，未購買 Apple 年費開發者憑證。
請雙擊執行旁邊的「一鍵解除 Gatekeeper 隔離」工具即可一秒解除阻擋！
EOF

# 5. 打包為 UDZO DMG
echo "正在建立 $DMG_NAME..."
rm -f "$DMG_NAME"
hdiutil create -volname "Battery Logger v2.0.0" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_NAME"
rm -rf "$STAGING_DIR"

if [ -d "/Users/matt/Desktop" ]; then
    cp -f "$DMG_NAME" "/Users/matt/Desktop/$DMG_NAME"
    echo "已同步複製至桌面：/Users/matt/Desktop/$DMG_NAME"
fi

echo "✅ DMG 打包完成：$DMG_NAME"
