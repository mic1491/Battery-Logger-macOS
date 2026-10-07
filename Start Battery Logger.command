#!/bin/zsh
cd "$(dirname "$0")"
if ! command -v python3 >/dev/null 2>&1; then
  echo "找不到 Python 3。請先安裝 Python 3，然後再雙擊此檔。"
  read -r "?按 Enter 結束。"
  exit 1
fi
exec python3 "$(dirname "$0")/BatteryLogger.py"
