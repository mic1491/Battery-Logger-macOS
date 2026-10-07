#!/bin/zsh
set -e

APP="/Applications/Battery Logger.app"
EXTENSION="$APP/Contents/PlugIns/BatteryLoggerWidget.appex"
EXTENSION_ID="local.codex.batterylogger.v2.widget"

if [[ ! -d "$EXTENSION" ]]; then
  echo "找不到小工具 extension：$EXTENSION"
  echo "請先確認 Battery Logger.app 已安裝在「應用程式」資料夾。"
  read -r "?按 Enter 結束。"
  exit 1
fi

echo "正在登記 Battery Logger 與內嵌小工具…"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
LOCAL_EXTENSION="${0:A:h}/Battery Logger.app/Contents/PlugIns/BatteryLoggerWidget.appex"
if [[ "$LOCAL_EXTENSION" != "$EXTENSION" && -d "$LOCAL_EXTENSION" ]]; then
  /usr/bin/pluginkit -r "$LOCAL_EXTENSION" || true
fi
/usr/bin/pluginkit -a "$EXTENSION"
/usr/bin/pluginkit -e use -p com.apple.widgetkit-extension -i "$EXTENSION_ID"

echo
echo "PlugInKit 登記結果："
/usr/bin/pluginkit -m -D -v -p com.apple.widgetkit-extension -i "$EXTENSION_ID"
echo
echo "登記成功只代表系統已發現擴充套件；仍需確認它能提供小工具內容。"
echo "請在「編輯小工具」中尋找 Battery Logger 的「電池摘要」與「電量趨勢」。"
read -r "?按 Enter 關閉此視窗。"
