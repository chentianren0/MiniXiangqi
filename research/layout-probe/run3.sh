#!/bin/zsh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd /Users/tianren/coding/minixiangqi/discussion-drafts/layout-probe
udid="$1"
xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1
xcrun simctl terminate "$udid" com.ppppvz.layoutprobe3 >/dev/null 2>&1
xcrun simctl uninstall "$udid" com.ppppvz.layoutprobe3 >/dev/null 2>&1
xcrun simctl install "$udid" LayoutProbe3.app || exit 1
xcrun simctl launch "$udid" com.ppppvz.layoutprobe3 >/dev/null 2>&1
sleep 10
c=$(xcrun simctl get_app_container "$udid" com.ppppvz.layoutprobe3 data 2>/dev/null)
cat "$c/Documents/probe3.txt" 2>/dev/null || echo "NO OUTPUT"
