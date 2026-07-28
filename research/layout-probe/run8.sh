#!/bin/zsh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd /Users/tianren/coding/minixiangqi/discussion-drafts/layout-probe
udid="$1"; label="$2"; ori="$3"   # ori = P or L
bid="com.ppppvz.layoutprobe8$ori"
xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1
xcrun simctl terminate "$udid" "$bid" >/dev/null 2>&1
xcrun simctl uninstall "$udid" "$bid" >/dev/null 2>&1
xcrun simctl install "$udid" "LayoutProbe8$ori.app" || { echo "INSTALL FAIL $label"; exit 1; }
xcrun simctl launch "$udid" "$bid" >/dev/null 2>&1
for i in {1..30}; do
  c=$(xcrun simctl get_app_container "$udid" "$bid" data 2>/dev/null)
  if [ -n "$c" ] && grep -q "@@DONE8@@" "$c/Documents/probe8.txt" 2>/dev/null; then break; fi
  sleep 2
done
c=$(xcrun simctl get_app_container "$udid" "$bid" data 2>/dev/null)
cp "$c/Documents/probe8.txt" "out8-$label-$ori.txt" 2>/dev/null && echo "OK $label $ori" || echo "NO OUTPUT $label $ori"
xcrun simctl terminate "$udid" "$bid" >/dev/null 2>&1
