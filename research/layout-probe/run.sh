#!/bin/zsh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd /Users/tianren/coding/minixiangqi/discussion-drafts/layout-probe
udid="$1"; label="$2"
echo "===================== $label ====================="
xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1
xcrun simctl terminate "$udid" com.ppppvz.layoutprobe >/dev/null 2>&1
xcrun simctl uninstall "$udid" com.ppppvz.layoutprobe >/dev/null 2>&1
xcrun simctl install "$udid" LayoutProbe.app || exit 1
xcrun simctl launch "$udid" com.ppppvz.layoutprobe >/dev/null 2>&1
sleep 15
c=$(xcrun simctl get_app_container "$udid" com.ppppvz.layoutprobe data 2>/dev/null)
cat "$c/Documents/probe.txt" 2>/dev/null || echo "NO OUTPUT ($c)"
