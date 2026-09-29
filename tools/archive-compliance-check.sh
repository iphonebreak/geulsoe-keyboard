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
#
# ★ 2026-09-29 2차 개정 (반론자2 C1–C3, `docs/release/v1.2.0-release-critique-code.md` 3절) — **거짓 통과 6건.**
#   1차 개정본도 실제 Release 아카이브의 결함 변이 6개를 **전부 exit 0**으로 통과시켰다:
#     C1 매니페스트 삭제·0바이트·사유 배열 비움 — `plutil | grep -c`가 읽기 실패를 「0종」으로 셌다
#     C2 익스텐션 제거·앱 실행 파일 이름 변경 — 실행 파일을 번들 이름으로 **추정**했고, 못 찾으면 검사를 **건너뛰었다**
#     C3 32바이트로 잘린 프레임워크 — `otool` 실패를 「코드 없는 껍데기」로 간주했다
#   그래서 지금은 **「못 쟀다」가 절대 「깨끗하다」가 되지 않게** 한다:
#     - 필수 대상(앱·키보드 번들 ID → `CFBundleExecutable` → Mach-O → (UUID, 아키텍처)가 같은 dSYM)을 **먼저 확정**하고,
#       하나라도 없으면 그 자리에서 실패한다. 예상 밖 익스텐션도 실패다(이 스크립트가 모르는 코드).
#     - **도구 오류(plutil·nm·otool·lipo·dwarfdump)는 실패**다. 숫자 0으로 바꾸지 않는다.
#     - 「코드 없는 껍데기」 예외는 **검증된 조건만** — 도구 성공 + 모든 아키텍처에 `__TEXT,__text`가 있고 크기 0.
#       코드가 있는 Mach-O는 전부 UUID가 맞는 dSYM이 있어야 한다(없으면 측정 불가 = 실패).
#     - 매니페스트는 존재·plist 파싱·필수 키·타입을 보고, required-reason 사유와 수집 항목을
#       **아래 기대값과 정확히** 비교한다(기대값은 9838c2e의 파일에서 뽑아 고정했다 — 매니페스트를 바꾸면 여기도 바꾼다).
#     - 양성 대조(앱 dSYM의 Firebase·키보드 dSYM의 자기 심볼)는 **필수**다 — 0이면 「못 쟀다」.
#
# 확인하는 것:
#   0) 필수 대상 확정 — 번들 ID · CFBundleExecutable · dSYM(UUID·아키텍처) · 번들 안 모든 Mach-O · 양성 대조
#   1) 버전 — 존재·형식, 앱과 익스텐션이 같은 값인가 (다르면 업로드 거절)
#   2) 수출 규정 — 열거한 암호 구현 이름 패턴이 0인가 (ITSAppUsesNonExemptEncryption=false 의 근거 중 하나)
#   3) 추적 표면 — 광고 전환 SDK·IDFA API 0, 추적 프레임워크 링크 0
#   4) 익스텐션 순수성 — 키보드에 Firebase 0, 시스템 밖 라이브러리 링크 0 (security.md 1순위 규칙)
#   5) 프라이버시 매니페스트 — 앱·키보드 모두 존재·파싱·필수 키·required-reason·수집 선언이 기대값과 일치
set -uo pipefail
shopt -s nullglob

ARCHIVE="${1:-}"
if [ -z "$ARCHIVE" ] || [ ! -d "$ARCHIVE" ]; then
  echo "사용법: bash tools/archive-compliance-check.sh <경로>.xcarchive" >&2; exit 2
fi

# ── 기대값 — 이 제품의 현재 사실(9838c2e의 번들·매니페스트에서 뽑았다). 바꾸려면 근거와 함께 여기를 고친다 ──
APP_BUNDLE_ID="com.charging.tadak"
EXT_BUNDLE_ID="com.charging.tadak.keyboard"
APP_EXE_NAME="Tadak"            # project.yml 타깃 이름에서 나온다 — 바뀌면 그 이유를 확인하고 여기를 고친다
EXT_EXE_NAME="TadakKeyboard"
# required-reason — 앱·키보드 같다: UserDefaults 1C8F.1(App Group 공유) · CA92.1(자기 전용 — 키보드 최근 이모지, 앱 동의 값)
EXPECTED_APP_API='{"NSPrivacyAccessedAPICategoryUserDefaults": ["1C8F.1", "CA92.1"]}'
EXPECTED_EXT_API='{"NSPrivacyAccessedAPICategoryUserDefaults": ["1C8F.1", "CA92.1"]}'
EXPECTED_APP_COLLECTED='["NSPrivacyCollectedDataTypeCoarseLocation", "NSPrivacyCollectedDataTypeCrashData", "NSPrivacyCollectedDataTypeDeviceID", "NSPrivacyCollectedDataTypeOtherDiagnosticData", "NSPrivacyCollectedDataTypeOtherUsageData", "NSPrivacyCollectedDataTypeProductInteraction"]'
EXPECTED_EXT_COLLECTED='[]'

TMP=$(mktemp -d "${TMPDIR:-/tmp}/archive-check.XXXXXX") || { echo "임시 디렉터리를 만들지 못했다" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

FAIL=0
say()  { printf '%s\n' "$*"; }
bad()  { printf '  ✗ %s\n' "$*" >&2; FAIL=1; }
ok()   { printf '  ✓ %s\n' "$*"; }
# 필수 대상을 확정하지 못하면 뒤 검사는 의미가 없다 — 그 자리에서 실패로 끝낸다
stop() { bad "$*"; echo; echo "결과: 실패 — 필수 대상을 확정하지 못해 측정할 수 없다" >&2; exit 1; }

is_macho() { file -b "$1" 2>/dev/null | grep -q 'Mach-O'; }
# Info.plist 값 — 읽기 실패는 비정상 종료로 돌려준다(빈 문자열과 구분)
info() { plutil -extract "$2" raw "$1/Info.plist" 2>/dev/null; }
# (UUID, 아키텍처) 쌍 전부 — 도구 실패면 비정상 종료
uuid_pairs() {
  local out; out=$(dwarfdump --uuid "$1" 2>/dev/null) || return 1
  printf '%s\n' "$out" | awk '$1=="UUID:" {print $2 $3}' | sort | tr '\n' ' '
}
# 바이너리와 (UUID, 아키텍처) 쌍이 전부 같은 dSYM의 DWARF 파일 — 없으면 빈 문자열
dsym_for() {
  local want; want=$(uuid_pairs "$1") || return 0
  [ -n "$want" ] || return 0
  local dwarf got
  for dwarf in "$DSYMS"/*.dSYM/Contents/Resources/DWARF/*; do
    [ -f "$dwarf" ] || continue
    got=$(uuid_pairs "$dwarf") || continue
    [ "$got" = "$want" ] && { echo "$dwarf"; return 0; }
  done
}
# 심볼 판정 대상 — nm -a 출력을 한 번만 떠 둔다. **nm 실패는 실패**다(0건으로 바꾸지 않는다)
SOURCES=(); NMS=()
add_source() {
  local f="$TMP/nm.${#SOURCES[@]}"
  if nm -a "$1" > "$f" 2>"$f.err"; then SOURCES+=("$1"); NMS+=("$f"); return 0; fi
  bad "nm 실패: ${1#"$ARCHIVE"/} — $(head -1 "$f.err")"; return 1
}
count() { grep -ciE "$2" "$1" || true; }

say "== 0) 필수 대상 확정 — 번들 ID · CFBundleExecutable · dSYM · 양성 대조 =="
APPS=("$ARCHIVE"/Products/Applications/*.app)
[ "${#APPS[@]}" -eq 1 ] || stop "Products/Applications 에 .app 이 정확히 1개여야 한다(찾은 수 ${#APPS[@]})"
APP="${APPS[0]}"
AID=$(info "$APP" CFBundleIdentifier) || stop "앱 Info.plist 의 CFBundleIdentifier 를 읽지 못했다"
[ "$AID" = "$APP_BUNDLE_ID" ] || stop "앱 번들 ID가 $APP_BUNDLE_ID 가 아니다: $AID"
AEXE=$(info "$APP" CFBundleExecutable) || stop "앱 CFBundleExecutable 을 읽지 못했다"
APP_BIN="$APP/$AEXE"
{ [ -f "$APP_BIN" ] && is_macho "$APP_BIN"; } || stop "앱 실행 파일이 없거나 Mach-O가 아니다: $AEXE"
ok "앱 $AID — 실행 파일 $AEXE (CFBundleExecutable)"
# 이름이 기대와 달라도 **검사는 CFBundleExecutable이 가리키는 실제 파일로 계속한다**(반론자2 C2 — 「앱을 계속 검사」).
# 다만 이 스크립트가 아는 제품 구조가 아니므로 결과는 실패다(사람이 이유를 확인하고 기대값을 고친다).
[ "$AEXE" = "$APP_EXE_NAME" ] || bad "앱 실행 파일 이름이 기대값($APP_EXE_NAME)과 다르다: $AEXE — 검사는 이 파일로 계속한다"

APPEX=""
for x in "$APP"/PlugIns/*.appex; do
  if ! xid=$(info "$x" CFBundleIdentifier); then bad "$(basename "$x") 의 Info.plist 를 읽지 못했다"; continue; fi
  if [ "$xid" = "$EXT_BUNDLE_ID" ]; then APPEX="$x"
  else bad "예상 밖 익스텐션 $(basename "$x") ($xid) — 이 스크립트가 모르는 코드다. 검사를 갱신하기 전에는 통과시키지 않는다"; fi
done
[ -n "$APPEX" ] || stop "키보드 익스텐션($EXT_BUNDLE_ID)이 아카이브에 없다"
EEXE=$(info "$APPEX" CFBundleExecutable) || stop "키보드 CFBundleExecutable 을 읽지 못했다"
APPEX_BIN="$APPEX/$EEXE"
{ [ -f "$APPEX_BIN" ] && is_macho "$APPEX_BIN"; } || stop "키보드 실행 파일이 없거나 Mach-O가 아니다: $EEXE"
ok "키보드 $EXT_BUNDLE_ID — 실행 파일 $EEXE (CFBundleExecutable)"
[ "$EEXE" = "$EXT_EXE_NAME" ] || bad "키보드 실행 파일 이름이 기대값($EXT_EXE_NAME)과 다르다: $EEXE — 검사는 이 파일로 계속한다"

DSYMS="$ARCHIVE/dSYMs"
[ -d "$DSYMS" ] || stop "아카이브에 dSYMs/ 가 없다 — 벗겨진 바이너리로는 심볼 검사가 죽는다. dSYM 포함 Release 아카이브에 돌려라"
APP_DWARF=$(dsym_for "$APP_BIN")
[ -n "$APP_DWARF" ] || stop "앱 실행 파일과 (UUID, 아키텍처)가 같은 dSYM이 없다(또는 dwarfdump 실패)"
APPEX_DWARF=$(dsym_for "$APPEX_BIN")
[ -n "$APPEX_DWARF" ] || stop "키보드 실행 파일과 (UUID, 아키텍처)가 같은 dSYM이 없다(또는 dwarfdump 실패)"
add_source "$APP_DWARF" || stop "앱 dSYM 심볼을 읽지 못했다"
APP_NM="${NMS[${#NMS[@]}-1]}"
add_source "$APPEX_DWARF" || stop "키보드 dSYM 심볼을 읽지 못했다"
APPEX_NM="${NMS[${#NMS[@]}-1]}"
say "  $AEXE ← ${APP_DWARF#"$DSYMS"/} (UUID·아키텍처 일치)"
say "  $EEXE ← ${APPEX_DWARF#"$DSYMS"/} (UUID·아키텍처 일치)"

# 번들 안 **모든** Mach-O(프레임워크·dylib·익스텐션 안쪽까지 — 깊이 제한 없음)
MACHOS=("$APP_BIN" "$APPEX_BIN")
while IFS= read -r -d '' b; do
  { [ "$b" = "$APP_BIN" ] || [ "$b" = "$APPEX_BIN" ]; } && continue
  is_macho "$b" || continue
  MACHOS+=("$b")
  rel="${b#"$APP"/}"
  d=$(dsym_for "$b")
  if [ -n "$d" ]; then
    say "  $rel ← ${d#"$DSYMS"/} (UUID·아키텍처 일치)"
    add_source "$d"
    continue
  fi
  # 코드 없는 껍데기 예외 — **검증된 조건만**: lipo·otool 성공 + 모든 아키텍처에 __TEXT,__text 가 있고 크기 0.
  # (번들된 FirebaseAnalytics·GoogleAppMeasurement는 원본이 정적 라이브러리라 실체가 앱 본체에 링크되고 — 앱 dSYM에서 잰다 —
  #  번들에는 빈 틀만 남는다. 도구가 실패했거나 __text 를 못 찾았으면 「코드 없음」이 아니라 「못 쟀다」다 — 반론자2 C3)
  if ! archs=$(lipo -archs "$b" 2>"$TMP/lipo.err"); then
    bad "$rel — lipo 실패($(head -1 "$TMP/lipo.err")) — 코드 없음으로 간주하지 않는다"; continue
  fi
  if ! ol=$(otool -arch all -l "$b" 2>"$TMP/otool.err"); then
    bad "$rel — otool 실패($(head -1 "$TMP/otool.err")) — 코드 없음으로 간주하지 않는다"; continue
  fi
  nar=$(printf '%s\n' "$archs" | wc -w | tr -d ' ')
  sizes=$(printf '%s\n' "$ol" | awk '$1=="sectname" && $2=="__text" {t=1; seg=""; next}
                                     t && $1=="segname" {seg=$2; next}
                                     t && $1=="size" { if (seg=="__TEXT") print $2; t=0 }')
  ntext=$(printf '%s\n' "$sizes" | grep -c . || true)
  nonzero=0
  for s in $sizes; do [ $((s)) -ne 0 ] && nonzero=1; done
  if [ "$nar" -gt 0 ] && [ "$ntext" -eq "$nar" ] && [ "$nonzero" -eq 0 ]; then
    say "  $rel ← 코드 없는 껍데기(아키텍처 $nar 개 모두 __text 0) — 실체는 앱 dSYM에서 잰다"
  else
    bad "$rel — 코드가 있거나(__text ≠ 0) 확인할 수 없는데(아키텍처 $nar, __text $ntext) UUID 맞는 dSYM이 없다 — 측정 불가"
  fi
done < <(find "$APP" -type f -print0)

# 양성 대조 — **필수**. 「0건」이 「깨끗함」인지 「못 잼」인지 가른다
PC_APP=$(count "$APP_NM" 'firebase|FIRApp|APMMeasurement')
[ "$PC_APP" -gt 0 ] && ok "양성 대조(앱 dSYM의 Firebase 심볼) $PC_APP 개 — 앱 측정이 살아 있다" \
                    || bad "양성 대조 0 — 앱에 Firebase가 있는데 심볼이 안 잡힌다. 측정이 죽었다"
PC_EXT=$(grep -c 'KeyboardViewController' "$APPEX_NM" || true)
[ "$PC_EXT" -gt 0 ] && ok "양성 대조(키보드 dSYM의 KeyboardViewController 심볼) $PC_EXT 개 — 키보드 측정이 살아 있다" \
                    || bad "양성 대조 0 — 키보드 자기 심볼이 안 잡힌다. 측정이 죽었다"
# 참고: 벗겨진 제출 바이너리에서 같은 대조를 재면 얼마인지(1차 결함의 증거로 남긴다)
if nm -a "$APP_BIN" > "$TMP/stripped.nm" 2>/dev/null; then
  say "  (참고) 벗겨진 앱 바이너리의 Firebase 심볼: $(count "$TMP/stripped.nm" 'firebase|FIRApp|APMMeasurement') 개"
fi

say "== 1) 버전 =="
AV=$(info "$APP" CFBundleShortVersionString) || { bad "앱 CFBundleShortVersionString 을 읽지 못했다"; AV=""; }
AB=$(info "$APP" CFBundleVersion) || { bad "앱 CFBundleVersion 을 읽지 못했다"; AB=""; }
EV=$(info "$APPEX" CFBundleShortVersionString) || { bad "키보드 CFBundleShortVersionString 을 읽지 못했다"; EV=""; }
EB=$(info "$APPEX" CFBundleVersion) || { bad "키보드 CFBundleVersion 을 읽지 못했다"; EB=""; }
say "  앱: $AV ($AB) · 키보드: $EV ($EB)"
[[ "$AV" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || bad "앱 버전 형식이 아니다: '$AV'"
[[ "$AB" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || bad "앱 빌드 번호 형식이 아니다: '$AB'"
if [ -n "$AV" ] && [ "$AV" = "$EV" ] && [ -n "$AB" ] && [ "$AB" = "$EB" ]; then ok "앱·키보드 버전 일치"
else bad "앱·키보드 버전 불일치 — 업로드 거절된다"; fi

say "== 2) 수출 규정 — 열거한 암호 구현 이름 (nm -a, dSYM 전체 심볼) =="
CRYPTO='bssl_g3|_EVP_|_AES_[a-z]|_RSA_[a-z]|BoringSSL|openssl|CCCrypt|_ccaes|_ccrsa'
T=0
for i in "${!NMS[@]}"; do
  c=$(count "${NMS[$i]}" "$CRYPTO")
  [ "$c" -gt 0 ] && say "    ${SOURCES[$i]#"$ARCHIVE"/}: $c"
  T=$((T+c))
done
ITS=$(info "$APP" ITSAppUsesNonExemptEncryption) || ITS="없음"
[ "$ITS" = "false" ] && ok "ITSAppUsesNonExemptEncryption = false" || bad "ITSAppUsesNonExemptEncryption = $ITS (false 여야 한다)"
if [ "$T" -eq 0 ]; then
  ok "열거한 암호 구현 이름 패턴 0건(심볼 판정 대상 ${#SOURCES[@]} 개) — 이름을 감춘 자체 구현까지 증명하지는 않는다(소스·의존성 검토와 함께 본다)"
else
  bad "암호화 심볼 $T 건 — false 근거가 무너진다. 사람이 재판단할 것"
fi

say "== 3) 추적 표면 =="
ADS=0; IDFA=0
for f in "${NMS[@]}"; do
  ADS=$((ADS+$(count "$f" '_OBJC_CLASS_\$_(ODC|GAD)|_\$s27GoogleAdsOnDeviceConversion')))
  IDFA=$((IDFA+$(count "$f" 'ASIdentifierManager|advertisingIdentifier|ATTrackingManager')))
done
[ -d "$APP/Frameworks/GoogleAdsOnDeviceConversion.framework" ] && bad "GoogleAdsOnDeviceConversion.framework 가 번들에 있다"
[ -d "$APP/Frameworks/GoogleAppMeasurementIdentitySupport.framework" ] && bad "GoogleAppMeasurementIdentitySupport.framework 가 번들에 있다"
[ "$ADS" -eq 0 ] && ok "광고 전환 SDK 클래스 0건(dSYM)" || bad "광고 전환 SDK 클래스 $ADS 건"
[ "$IDFA" -eq 0 ] && ok "IDFA/ATT API 0건(dSYM)" || bad "IDFA/ATT API $IDFA 건"
# 보조 근거 — 링크한 프레임워크(심볼이 벗겨져도 로드 명령은 남는다). **otool 실패는 실패**다
LINKED=""
for b in "${MACHOS[@]}"; do
  if ! lo=$(otool -L "$b" 2>"$TMP/otool-L.err"); then bad "otool -L 실패: ${b#"$APP"/} — $(head -1 "$TMP/otool-L.err")"; continue; fi
  hit=$(printf '%s\n' "$lo" | grep -E 'AdSupport\.framework|AppTrackingTransparency\.framework' || true)
  [ -n "$hit" ] && LINKED="$LINKED ${b#"$APP"/}"
done
[ -z "$LINKED" ] && ok "otool -L — AdSupport·AppTrackingTransparency 링크 0건(Mach-O ${#MACHOS[@]} 개)" || bad "otool -L — 추적 프레임워크 링크:$LINKED"

say "== 4) 익스텐션 순수성 =="
FB=$(count "$APPEX_NM" 'firebase|FIRApp|APMMeasurement')
[ "$FB" -eq 0 ] && ok "키보드에 Firebase 심볼 0건(dSYM, 양성 대조 $PC_EXT 개)" \
                || bad "키보드에 Firebase 심볼 $FB 건 — security.md 1순위 규칙 위반"
if ! elo=$(otool -L "$APPEX_BIN" 2>"$TMP/otool-ext.err"); then
  bad "otool -L 실패: 키보드 실행 파일 — $(head -1 "$TMP/otool-ext.err")"
else
  # 시스템 밖 라이브러리(번들 프레임워크·@rpath dylib 등)를 하나라도 링크하면 실패
  EXTRA=$(printf '%s\n' "$elo" | awk '/^\t/ {print $1}' | grep -vE '^(/System/Library/|/usr/lib/)' || true)
  [ -z "$EXTRA" ] && ok "otool -L — 키보드는 시스템 라이브러리(/System/Library·/usr/lib)만 링크한다" \
                  || bad "otool -L — 키보드가 시스템 밖 라이브러리를 링크한다: $(printf '%s' "$EXTRA" | tr '\n' ' ')"
fi

say "== 5) 프라이버시 매니페스트 — 존재·파싱·필수 키·required-reason·수집 선언 =="
python3 - "$APP/PrivacyInfo.xcprivacy" "앱" "$EXPECTED_APP_API" "$EXPECTED_APP_COLLECTED" \
           "$APPEX/PrivacyInfo.xcprivacy" "키보드" "$EXPECTED_EXT_API" "$EXPECTED_EXT_COLLECTED" <<'PY'
import json, plistlib, sys

failed = False
def ok(msg):  print(f"  ✓ {msg}")
def bad(msg):
    global failed
    failed = True
    print(f"  ✗ {msg}", file=sys.stderr)

def check(path, who, expected_api, expected_collected):
    try:
        with open(path, "rb") as f:
            data = plistlib.load(f)
    except FileNotFoundError:
        return bad(f"{who} PrivacyInfo.xcprivacy 가 없다")
    except Exception as e:
        return bad(f"{who} PrivacyInfo.xcprivacy 를 plist로 읽지 못했다 — {type(e).__name__}")
    if not isinstance(data, dict):
        return bad(f"{who} 매니페스트 최상위가 사전이 아니다")
    types = {"NSPrivacyTracking": bool, "NSPrivacyTrackingDomains": list,
             "NSPrivacyCollectedDataTypes": list, "NSPrivacyAccessedAPITypes": list}
    for key, kind in types.items():
        if key not in data:
            return bad(f"{who} 매니페스트에 필수 키 {key} 가 없다")
        if not isinstance(data[key], kind):
            return bad(f"{who} {key} 의 타입이 {kind.__name__} 가 아니다")
    ok(f"{who} 매니페스트 — 존재·파싱·필수 키 4개")

    if data["NSPrivacyTracking"] is not False:
        bad(f"{who} NSPrivacyTracking 이 false 가 아니다")
    elif data["NSPrivacyTrackingDomains"]:
        bad(f"{who} NSPrivacyTrackingDomains 가 비어 있지 않다")
    else:
        ok(f"{who} NSPrivacyTracking = false · 추적 도메인 0")

    # required-reason — 카테고리별 사유 집합이 기대값과 정확히 같아야 한다
    api = {}
    for item in data["NSPrivacyAccessedAPITypes"]:
        if not isinstance(item, dict) or not isinstance(item.get("NSPrivacyAccessedAPIType"), str) \
                or not isinstance(item.get("NSPrivacyAccessedAPITypeReasons"), list):
            return bad(f"{who} NSPrivacyAccessedAPITypes 항목 형식이 틀렸다")
        api.setdefault(item["NSPrivacyAccessedAPIType"], set()).update(item["NSPrivacyAccessedAPITypeReasons"])
    want = {k: set(v) for k, v in expected_api.items()}
    if api == want:
        ok(f"{who} required-reason — " + " · ".join(f"{k.replace('NSPrivacyAccessedAPICategory', '')} {', '.join(sorted(v))}" for k, v in sorted(api.items())))
    else:
        bad(f"{who} required-reason 이 기대값과 다르다 — 실제 {dict((k, sorted(v)) for k, v in api.items())} / 기대 {expected_api}")

    # 수집 선언 — 종류 집합이 기대값과 같고, 각 항목에 연결·추적·목적이 있으며 추적은 false
    kinds = []
    for item in data["NSPrivacyCollectedDataTypes"]:
        if not isinstance(item, dict) or not isinstance(item.get("NSPrivacyCollectedDataType"), str) \
                or not isinstance(item.get("NSPrivacyCollectedDataTypeLinked"), bool) \
                or not isinstance(item.get("NSPrivacyCollectedDataTypeTracking"), bool) \
                or not item.get("NSPrivacyCollectedDataTypePurposes"):
            return bad(f"{who} NSPrivacyCollectedDataTypes 항목 형식이 틀렸다")
        if item["NSPrivacyCollectedDataTypeTracking"]:
            bad(f"{who} 수집 항목 {item['NSPrivacyCollectedDataType']} 이 추적으로 선언됐다")
        kinds.append(item["NSPrivacyCollectedDataType"])
    if sorted(kinds) == sorted(expected_collected):
        ok(f"{who} 수집 선언 {len(kinds)} 종 — 기대값과 일치")
    else:
        bad(f"{who} 수집 선언이 기대값과 다르다 — 실제 {sorted(kinds)} / 기대 {sorted(expected_collected)}")

args = sys.argv[1:]
for i in range(0, len(args), 4):
    path, who, api, collected = args[i:i + 4]
    check(path, who, json.loads(api), json.loads(collected))
sys.exit(1 if failed else 0)
PY
[ $? -eq 0 ] || FAIL=1

echo
[ "$FAIL" -eq 0 ] && { echo "결과: 통과 — 업로드해도 되는 상태"; exit 0; }
echo "결과: 실패 — 위 ✗ 항목을 해결하기 전에 업로드하지 마라" >&2; exit 1
