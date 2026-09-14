#!/bin/bash
# 제출용 아카이브 규정 점검 — App Store 업로드 **직전**에 아카이브 본체에 돌린다.
#
# 사용법: bash tools/archive-compliance-check.sh <경로>.xcarchive
#
# 왜 필요한가 — 검사 대상이 "소스"나 "DerivedData 디버그 빌드"가 아니라 **실제로 제출되는
# 바이너리**여야 한다. 디버그 빌드에는 .debug.dylib 분리 등 차이가 있고, 무엇보다
# `nm -u`(미정의 심볼)로는 **정적 링크된 암호 라이브러리를 원리상 못 잡는다** —
# 정적으로 들어온 것은 정의된 심볼이라 -u 에 안 나온다(반론자4 지적 2026-09-14).
# 그래서 이 스크립트는 전부 `nm -a`(전체 심볼)로 본다.
#
# 확인하는 것 5가지:
#   1) 버전 — 앱과 익스텐션이 같은 값인가 (다르면 업로드 거절)
#   2) 수출 규정 — 자체 암호화 구현이 정말 0인가 (ITSAppUsesNonExemptEncryption=false 의 근거)
#   3) 추적 표면 — 광고 전환 SDK·IDFA API가 정말 0인가 (NSPrivacyTracking=false 의 근거)
#   4) 익스텐션 순수성 — 키보드에 Firebase가 0인가 (security.md 1순위 규칙)
#   5) 프라이버시 매니페스트가 실려 있고 수집 선언이 비어 있지 않은가
set -uo pipefail

ARCHIVE="${1:-}"
if [ -z "$ARCHIVE" ] || [ ! -d "$ARCHIVE" ]; then
  echo "사용법: bash tools/archive-compliance-check.sh <경로>.xcarchive" >&2; exit 2
fi
APP=$(find "$ARCHIVE/Products/Applications" -maxdepth 1 -name '*.app' | head -1)
[ -d "$APP" ] || { echo "아카이브에서 .app 을 못 찾았다: $ARCHIVE" >&2; exit 2; }
APPEX=$(find "$APP/PlugIns" -maxdepth 1 -name '*.appex' | head -1)

FAIL=0
say() { printf '%s\n' "$*"; }
bad() { printf '  ✗ %s\n' "$*" >&2; FAIL=1; }
ok()  { printf '  ✓ %s\n' "$*"; }

# 검사 대상 Mach-O 전부 (앱 본체 + 익스텐션 + 프레임워크)
binaries() {
  { echo "$APP/$(basename "${APP%.app}")"
    [ -n "$APPEX" ] && echo "$APPEX/$(basename "${APPEX%.appex}")"
    ls "$APP"/Frameworks/*/* 2>/dev/null
  } | while read -r b; do
    [ -f "$b" ] && file "$b" 2>/dev/null | grep -q "Mach-O" && echo "$b"
  done
}

say "== 1) 버전 =="
AV=$(plutil -extract CFBundleShortVersionString raw "$APP/Info.plist" 2>/dev/null)
AB=$(plutil -extract CFBundleVersion raw "$APP/Info.plist" 2>/dev/null)
say "  앱: $AV ($AB)"
if [ -n "$APPEX" ]; then
  EV=$(plutil -extract CFBundleShortVersionString raw "$APPEX/Info.plist" 2>/dev/null)
  EB=$(plutil -extract CFBundleVersion raw "$APPEX/Info.plist" 2>/dev/null)
  say "  익스텐션: $EV ($EB)"
  [ "$AV" = "$EV" ] && [ "$AB" = "$EB" ] && ok "앱·익스텐션 버전 일치" || bad "앱·익스텐션 버전 불일치 — 업로드 거절된다"
fi

say "== 2) 수출 규정 — 자체 암호화 구현 (nm -a, 전체 심볼) =="
CRYPTO='bssl_g3|_EVP_|_AES_[a-z]|_RSA_[a-z]|BoringSSL|openssl|CCCrypt|_ccaes|_ccrsa'
T=0
while read -r b; do
  c=$(nm -a "$b" 2>/dev/null | grep -cE "$CRYPTO")
  [ "$c" -gt 0 ] && say "    $(basename "$b"): $c"
  T=$((T+c))
done < <(binaries)
ITS=$(plutil -extract ITSAppUsesNonExemptEncryption raw "$APP/Info.plist" 2>/dev/null || echo "없음")
say "  ITSAppUsesNonExemptEncryption = $ITS"
if [ "$T" -eq 0 ]; then
  ok "자체 암호화 구현 0건 — OS 제공 HTTPS/TLS만 사용. false 근거 성립"
else
  bad "암호화 심볼 $T 건 — false 근거가 무너진다. 사람이 재판단할 것"
fi

say "== 3) 추적 표면 =="
ADS=0; IDFA=0
while read -r b; do
  ADS=$((ADS+$(nm -a "$b" 2>/dev/null | grep -cE '_OBJC_CLASS_\$_(ODC|GAD)|_\$s27GoogleAdsOnDeviceConversion')))
  IDFA=$((IDFA+$(nm -a "$b" 2>/dev/null | grep -ci 'ASIdentifierManager\|advertisingIdentifier\|ATTrackingManager')))
done < <(binaries)
[ -d "$APP/Frameworks/GoogleAdsOnDeviceConversion.framework" ] && bad "GoogleAdsOnDeviceConversion.framework 가 번들에 있다"
[ -d "$APP/Frameworks/GoogleAppMeasurementIdentitySupport.framework" ] && bad "GoogleAppMeasurementIdentitySupport.framework 가 번들에 있다"
[ "$ADS" -eq 0 ] && ok "광고 전환 SDK 클래스 0건" || bad "광고 전환 SDK 클래스 $ADS 건"
[ "$IDFA" -eq 0 ] && ok "IDFA/ATT API 0건" || bad "IDFA/ATT API $IDFA 건"
TRK=$(plutil -extract NSPrivacyTracking raw "$APP/PrivacyInfo.xcprivacy" 2>/dev/null)
[ "$TRK" = "false" ] && ok "NSPrivacyTracking = false" || bad "NSPrivacyTracking = $TRK"

say "== 4) 익스텐션 순수성 =="
if [ -n "$APPEX" ]; then
  FB=$(nm -a "$APPEX/$(basename "${APPEX%.appex}")" 2>/dev/null | grep -ci 'firebase\|FIRApp\|APMMeasurement')
  [ "$FB" -eq 0 ] && ok "키보드 익스텐션에 Firebase 심볼 0건" || bad "익스텐션에 Firebase 심볼 $FB 건 — security.md 1순위 규칙 위반"
fi

say "== 5) 프라이버시 매니페스트 =="
N=$(plutil -p "$APP/PrivacyInfo.xcprivacy" 2>/dev/null | grep -c 'NSPrivacyCollectedDataType"')
[ "$N" -gt 0 ] && ok "앱 수집 선언 $N 종" || bad "앱 수집 선언 0종 — 번들에 측정 엔진이 있으면 심사 자동 거절"
if [ -n "$APPEX" ]; then
  EN=$(plutil -p "$APPEX/PrivacyInfo.xcprivacy" 2>/dev/null | grep -c 'NSPrivacyCollectedDataType"')
  [ "$EN" -eq 0 ] && ok "익스텐션 수집 선언 0종 (Firebase 없으므로 맞다)" || bad "익스텐션이 수집을 선언한다 ($EN 종) — 실태와 맞는지 확인"
fi

echo
[ "$FAIL" -eq 0 ] && { echo "결과: 통과 — 업로드해도 되는 상태"; exit 0; }
echo "결과: 실패 — 위 ✗ 항목을 해결하기 전에 업로드하지 마라" >&2; exit 1
