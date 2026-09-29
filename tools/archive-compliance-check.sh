#!/bin/bash
# 제출용 아카이브 규정 점검 — App Store 업로드 **직전**에 **dSYM이 들어 있는 Release 아카이브**에 돌린다.
#
# 사용법: bash tools/archive-compliance-check.sh <경로>.xcarchive
#
# 왜 필요한가 — 검사 대상이 "소스"나 "DerivedData 디버그 빌드"가 아니라 **실제로 제출되는
# 바이너리**여야 한다. 디버그 빌드에는 .debug.dylib 분리 등 차이가 있고, 무엇보다
# `nm -u`(미정의 심볼)로는 **정적 링크된 암호 라이브러리를 원리상 못 잡는다** —
# 정적으로 들어온 것은 정의된 심볼이라 -u 에 안 나온다(반론자4 지적 2026-09-14).
# 그래서 이 스크립트는 전부 `nm -a`(전체 심볼)로 본다.
#
# ★ 2026-09-29 개정 (검증자 감사 1차) — **판정 근거를 dSYM으로 옮겼다.**
#   Release 아카이브의 앱 본체·프레임워크는 **심볼이 벗겨져(strip)** 있다. 그래서 옛 스크립트의
#   암호·광고/IDFA 검사는 **양성 대조(앱에 분명히 들어 있는 Firebase 심볼)까지 0**이었다 —
#   측정이 죽은 채로 「통과」를 찍었다. 검증자가 아카이브의 `dSYMs/`로 다시 재니 Firebase 양성
#   4,609개가 잡히는 상태에서 암호·광고·IDFA 0(깨끗)이었다. **v1.1.0 때의 통과도 같은 약점이었을 수 있다.**
#   그래서 지금은:
#     - 심볼 판정은 **dSYM의 DWARF 파일**(벗기기 전 심볼 표를 그대로 갖고 있다)로 한다.
#       앱·익스텐션의 dSYM이 없거나 바이너리와 UUID가 다르면 **실패**다(조용한 통과 금지).
#     - **양성 대조가 0이면 실패**다 — 앱 dSYM의 Firebase 심볼, 익스텐션 dSYM의 자기 모듈 심볼이
#       0이면 「깨끗하다」가 아니라 「못 쟀다」이다. 이것이 이번 결함의 재발 방지 핵심이다.
#     - `otool -L`(링크한 프레임워크)은 심볼과 무관하게 동작하므로 보조 근거로 함께 본다.
#
# 확인하는 것:
#   0) 측정 준비 — dSYM 존재·UUID 일치·양성 대조(측정이 살아 있는가)
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
DSYMS="$ARCHIVE/dSYMs"

FAIL=0
say() { printf '%s\n' "$*"; }
bad() { printf '  ✗ %s\n' "$*" >&2; FAIL=1; }
ok()  { printf '  ✓ %s\n' "$*"; }

# 번들 안 Mach-O 전부 (앱 본체 + 익스텐션 + 프레임워크) — 벗겨진 제출 바이너리
binaries() {
  { echo "$APP/$(basename "${APP%.app}")"
    [ -n "$APPEX" ] && echo "$APPEX/$(basename "${APPEX%.appex}")"
    ls "$APP"/Frameworks/*/* 2>/dev/null
  } | while read -r b; do
    [ -f "$b" ] && file "$b" 2>/dev/null | grep -q "Mach-O" && echo "$b"
  done
}

uuids() { dwarfdump --uuid "$1" 2>/dev/null | awk '{print $2}' | sort | tr '\n' ' '; }

# 바이너리와 UUID가 같은 dSYM의 DWARF 파일 — 없으면 빈 문자열
dsym_for() {
  local want; want=$(uuids "$1")
  [ -n "$want" ] || return 0
  local dwarf
  for dwarf in "$DSYMS"/*.dSYM/Contents/Resources/DWARF/*; do
    [ -f "$dwarf" ] || continue
    [ "$(uuids "$dwarf")" = "$want" ] && { echo "$dwarf"; return 0; }
  done
}

say "== 0) 측정 준비 — dSYM · UUID · 양성 대조 =="
if [ ! -d "$DSYMS" ] || [ -z "$(ls -A "$DSYMS" 2>/dev/null)" ]; then
  bad "아카이브에 dSYMs/ 가 없거나 비었다 — 벗겨진 바이너리로는 심볼 검사가 죽는다(2026-09-29). dSYM 포함 Release 아카이브에 돌려라"
  echo; echo "결과: 실패 — 측정할 수 없다" >&2; exit 1
fi
# 심볼 판정에 쓸 파일: 바이너리마다 짝 dSYM(없으면 사유와 함께 표시)
SOURCES=()
APP_BIN="$APP/$(basename "${APP%.app}")"
APPEX_BIN=""; [ -n "$APPEX" ] && APPEX_BIN="$APPEX/$(basename "${APPEX%.appex}")"
APP_DWARF=""; APPEX_DWARF=""
while read -r b; do
  d=$(dsym_for "$b")
  name=$(basename "$b")
  if [ -n "$d" ]; then
    say "  $name ← dSYM $(basename "$(dirname "$(dirname "$(dirname "$(dirname "$d")")")")") (UUID 일치)"
    SOURCES+=("$d")
    [ "$b" = "$APP_BIN" ] && APP_DWARF="$d"
    [ "$b" = "$APPEX_BIN" ] && APPEX_DWARF="$d"
  elif [ "$b" = "$APP_BIN" ] || [ "$b" = "$APPEX_BIN" ]; then
    bad "$name 의 dSYM이 없거나 UUID가 다르다 — 이 바이너리의 심볼을 잴 수 없다"
  else
    # 미리 빌드된 프레임워크(xcframework)는 dSYM이 없을 수 있다 — 바이너리 자체를 재되, 심볼이 있어야 인정한다
    # ★ 단, **코드가 없는 껍데기**(`__text` 크기 0)는 잴 대상이 아니다 — 번들된 FirebaseAnalytics·GoogleAppMeasurement는
    #   원본이 정적 라이브러리라 실체가 앱 본체에 링크되고(앱 dSYM에서 잰다) 번들에는 빈 틀만 남는다. 이것을 「측정 불가」로
    #   떨어뜨리면 정상 아카이브가 늘 실패한다(검증자 2026-09-29 — 거짓 실패). 코드가 있는데 심볼이 0인 것만 실패다.
    tsz=$(otool -l "$b" 2>/dev/null | awk '/sectname __text/{f=1} f && $1=="size" {print $2; exit}')
    if [ -z "$tsz" ] || [ $((tsz)) -eq 0 ]; then
      say "  $name ← 코드 없는 껍데기(__text 0) — 실체는 앱 dSYM에서 잰다, 건너뜀"
      continue
    fi
    n=$(nm -a "$b" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$n" -gt 0 ]; then
      say "  $name ← dSYM 없음, 바이너리 심볼 $n 개로 잰다"
      SOURCES+=("$b")
    else
      bad "$name — dSYM도 없고 바이너리 심볼도 0이다(측정 불가)"
    fi
  fi
done < <(binaries)

# 양성 대조 — 「0건」이 「깨끗함」인지 「못 잼」인지 가른다
if [ -n "$APP_DWARF" ]; then
  PC_APP=$(nm -a "$APP_DWARF" 2>/dev/null | grep -ciE 'firebase|FIRApp|APMMeasurement')
  [ "$PC_APP" -gt 0 ] && ok "양성 대조(앱 dSYM의 Firebase 심볼) $PC_APP 개 — 앱 측정이 살아 있다" \
                      || bad "양성 대조 0 — 앱에 Firebase가 있는데 심볼이 안 잡힌다. 측정이 죽었다"
fi
if [ -n "$APPEX_DWARF" ]; then
  PC_EXT=$(nm -a "$APPEX_DWARF" 2>/dev/null | grep -c 'KeyboardViewController')
  [ "$PC_EXT" -gt 0 ] && ok "양성 대조(익스텐션 dSYM의 KeyboardViewController 심볼) $PC_EXT 개 — 익스텐션 측정이 살아 있다" \
                      || bad "양성 대조 0 — 익스텐션 자기 심볼이 안 잡힌다. 측정이 죽었다"
fi
# 참고: 벗겨진 제출 바이너리에서 같은 대조를 재면 얼마인지(이번 결함의 증거로 남긴다)
say "  (참고) 벗겨진 앱 바이너리의 Firebase 심볼: $(nm -a "$APP_BIN" 2>/dev/null | grep -ciE 'firebase|FIRApp|APMMeasurement') 개"

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

say "== 2) 수출 규정 — 자체 암호화 구현 (nm -a, dSYM 전체 심볼) =="
CRYPTO='bssl_g3|_EVP_|_AES_[a-z]|_RSA_[a-z]|BoringSSL|openssl|CCCrypt|_ccaes|_ccrsa'
T=0
for s in "${SOURCES[@]}"; do
  c=$(nm -a "$s" 2>/dev/null | grep -cE "$CRYPTO")
  [ "$c" -gt 0 ] && say "    $(basename "$s"): $c"
  T=$((T+c))
done
ITS=$(plutil -extract ITSAppUsesNonExemptEncryption raw "$APP/Info.plist" 2>/dev/null || echo "없음")
say "  ITSAppUsesNonExemptEncryption = $ITS"
if [ "$T" -eq 0 ]; then
  ok "자체 암호화 구현 0건(심볼 판정 대상 ${#SOURCES[@]} 개) — OS 제공 HTTPS/TLS만 사용. false 근거 성립"
else
  bad "암호화 심볼 $T 건 — false 근거가 무너진다. 사람이 재판단할 것"
fi

say "== 3) 추적 표면 =="
ADS=0; IDFA=0
for s in "${SOURCES[@]}"; do
  ADS=$((ADS+$(nm -a "$s" 2>/dev/null | grep -cE '_OBJC_CLASS_\$_(ODC|GAD)|_\$s27GoogleAdsOnDeviceConversion')))
  IDFA=$((IDFA+$(nm -a "$s" 2>/dev/null | grep -ci 'ASIdentifierManager\|advertisingIdentifier\|ATTrackingManager')))
done
[ -d "$APP/Frameworks/GoogleAdsOnDeviceConversion.framework" ] && bad "GoogleAdsOnDeviceConversion.framework 가 번들에 있다"
[ -d "$APP/Frameworks/GoogleAppMeasurementIdentitySupport.framework" ] && bad "GoogleAppMeasurementIdentitySupport.framework 가 번들에 있다"
[ "$ADS" -eq 0 ] && ok "광고 전환 SDK 클래스 0건(dSYM)" || bad "광고 전환 SDK 클래스 $ADS 건"
[ "$IDFA" -eq 0 ] && ok "IDFA/ATT API 0건(dSYM)" || bad "IDFA/ATT API $IDFA 건"
# 보조 근거 — 링크한 프레임워크(심볼이 벗겨져도 로드 명령은 남는다)
LINKED=$(binaries | while read -r b; do otool -L "$b" 2>/dev/null | grep -E 'AdSupport\.framework|AppTrackingTransparency\.framework' | sed "s|^|$(basename "$b"): |"; done)
[ -z "$LINKED" ] && ok "otool -L — AdSupport·AppTrackingTransparency 링크 0건" || bad "otool -L — 추적 프레임워크 링크: $LINKED"
TRK=$(plutil -extract NSPrivacyTracking raw "$APP/PrivacyInfo.xcprivacy" 2>/dev/null)
[ "$TRK" = "false" ] && ok "NSPrivacyTracking = false" || bad "NSPrivacyTracking = $TRK"

say "== 4) 익스텐션 순수성 =="
if [ -n "$APPEX" ]; then
  if [ -n "$APPEX_DWARF" ]; then
    FB=$(nm -a "$APPEX_DWARF" 2>/dev/null | grep -ci 'firebase\|FIRApp\|APMMeasurement')
    [ "$FB" -eq 0 ] && ok "키보드 익스텐션에 Firebase 심볼 0건(dSYM, 양성 대조 ${PC_EXT:-0} 개)" \
                    || bad "익스텐션에 Firebase 심볼 $FB 건 — security.md 1순위 규칙 위반"
  fi
  EXTLINK=$(otool -L "$APPEX_BIN" 2>/dev/null | grep -ciE 'firebase|GoogleAppMeasurement|@rpath/.*\.framework')
  [ "$EXTLINK" -eq 0 ] && ok "otool -L — 익스텐션이 번들 프레임워크(Firebase 등)를 링크하지 않는다" \
                       || bad "otool -L — 익스텐션이 번들 프레임워크를 $EXTLINK 개 링크한다"
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
