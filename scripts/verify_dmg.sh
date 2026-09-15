#!/bin/bash
# 配布前チェック: 引数の DMG が本当に配れるものか判定する
set -uo pipefail
dmg="${1:?usage: verify_dmg.sh <dmg>}"
mnt=$(hdiutil attach -nobrowse -readonly "$dmg" | grep -o '/Volumes/.*' | head -1)
plist="$mnt/Hotbar.app/Contents/Info.plist"
bin="$mnt/Hotbar.app/Contents/MacOS/Hotbar"
fail=0
check() { # name expected actual
  if [ "$2" = "$3" ]; then printf '  ✅ %-22s %s\n' "$1" "$3"
  else printf '  🔴 %-22s %s  (期待: %s)\n' "$1" "$3" "$2"; fail=1; fi
}
echo "=== $dmg ==="
printf '  ℹ️  %-22s %s\n' "version" "$(defaults read "$plist" CFBundleShortVersionString)"
# 1. Polar 設定は Info.plist が正。バイナリの strings はソースのフォールバック文字列を拾うので使えない
check "PolarAPIBaseURL"  "https://api.polar.sh/v1" "$(defaults read "$plist" PolarAPIBaseURL 2>/dev/null)"
check "PolarOrganizationID" "5feb984d-234f-4fd9-b3e1-516abc5efd04" "$(defaults read "$plist" PolarOrganizationID 2>/dev/null)"
check "PolarProductID"   "6c230044-c164-4e2e-9fe1-52c747d1b7de" "$(defaults read "$plist" PolarProductID 2>/dev/null)"
co=$(defaults read "$plist" PolarCheckoutURL 2>/dev/null)
case "$co" in
  https://buy.polar.sh/polar_cl_*) printf '  ✅ %-22s %s\n' "PolarCheckoutURL" "$co" ;;
  *) printf '  🔴 %-22s %s  (期待: https://buy.polar.sh/polar_cl_…)\n' "PolarCheckoutURL" "$co"; fail=1 ;;
esac
# 2. ライセンス再検証が入った版か（これはソースの文字列リテラルなので strings で正しく判定できる）
n=$(strings "$bin" | grep -c licenseLastValidatedAt)
if [ "$n" -gt 0 ]; then printf '  ✅ %-22s %s 件\n' "licenseLastValidatedAt" "$n"
else printf '  🔴 %-22s 0 件（defaults write で恒久解除できる版）\n' "licenseLastValidatedAt"; fail=1; fi
# 3. 署名・公証
spctl --assess --type exec "$mnt/Hotbar.app" >/dev/null 2>&1 \
  && printf '  ✅ %-22s accepted / Notarized Developer ID\n' "spctl" \
  || { printf '  🔴 %-22s rejected\n' "spctl"; fail=1; }
xcrun stapler validate "$mnt/Hotbar.app" >/dev/null 2>&1 \
  && printf '  ✅ %-22s app OK\n' "stapler" || { printf '  🔴 %-22s app NG\n' "stapler"; fail=1; }
hdiutil detach "$mnt" -quiet
echo
[ "$fail" -eq 0 ] && echo "✅ 配って良い" || echo "🔴 配らないこと"
exit $fail
