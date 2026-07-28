#!/bin/zsh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd /Users/tianren/coding/minixiangqi/discussion-drafts/layout-probe
u="$1"; n="$2"
xcrun simctl bootstatus "$u" -b >/dev/null 2>&1
xcrun simctl uninstall "$u" com.ppppvz.layoutprobe >/dev/null 2>&1
xcrun simctl install "$u" LayoutProbe.app >/dev/null 2>&1 || { echo "$n INSTALL FAIL"; exit 1; }
xcrun simctl launch "$u" com.ppppvz.layoutprobe >/dev/null 2>&1
sleep 13
c=$(xcrun simctl get_app_container "$u" com.ppppvz.layoutprobe data 2>/dev/null)
printf "%-12s " "$n"
grep -m1 "^screen.bounds" "$c/Documents/probe.txt" 2>/dev/null | tr '\n' ' '
grep -m1 "^window.safeAreaInsets" "$c/Documents/probe.txt" 2>/dev/null | tr '\n' ' '
grep -m1 "^tabBar.frame" "$c/Documents/probe.txt" 2>/dev/null | tr '\n' ' '
grep -m1 "^USABLE" "$c/Documents/probe.txt" 2>/dev/null
