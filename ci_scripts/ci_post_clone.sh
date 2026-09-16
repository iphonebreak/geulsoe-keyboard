#!/bin/sh

# Xcode Cloud post-clone 훅 — 저장소를 clone한 직후 실행된다.
#
# 왜 필요한가: 이 저장소는 `Tadak.xcodeproj`를 **커밋하지 않는다**(`project.yml`이 SSOT,
# `.gitignore:2`). Xcode Cloud는 저장소를 clone할 뿐이므로 빌드할 프로젝트 파일이 없다.
# 여기서 XcodeGen으로 만들어 준다.
#
# ## 애플 문서에서 확인한 제약 (2026-09-11, developer.apple.com JSON API로 원문 확인)
#
# 1. 위치·이름: 스크립트는 `ci_scripts` 디렉터리에 있어야 하고, 그 디렉터리는
#    **Xcode 프로젝트/워크스페이스와 같은 디렉터리**에 있어야 한다. 이름은 정확히
#    `ci_post_clone.sh` / `ci_pre_xcodebuild.sh` / `ci_post_xcodebuild.sh` 셋뿐이다.
# 2. **작업 디렉터리가 `ci_scripts`다** — 원문: "Xcode Cloud runs your custom build scripts
#    with this directory as the root directory." 그래서 아래에서 **반드시 저장소로 이동**한다.
# 3. 실행 권한 + shebang이 **둘 다** 있어야 한다. 원문: "If you don't include a shebang ...
#    or forget to make the file executable, Xcode Cloud runs the script as `zsh $filename`,
#    which ... can cause a failing build."
# 4. `sudo`를 쓸 수 없다. 원문: "You can't obtain administrator privileges by using `sudo`."
# 5. 0이 아닌 종료 코드를 내야 Xcode Cloud가 빌드를 실패로 처리한다.
#
# ## 아직 확인하지 못한 것 — 이 스크립트의 가장 큰 위험
#
# 같은 문서에 이런 문장이 있다: "Files you create with a custom build script aren't available
# to other custom build scripts, and Xcode Cloud deletes any files a custom build script creates."
# 이 문장이 **`ci_scripts` 안에서 만든 임시 파일**을 뜻하는지, **clone된 저장소에 쓴 파일까지**
# 뜻하는지 문서가 명시하지 않는다. 후자라면 여기서 만든 `Tadak.xcodeproj`가 지워져 빌드가 깨진다.
# XcodeGen을 post-clone에서 돌리는 것은 널리 쓰이는 방식이지만 **우리는 실측하지 않았다.**
# 첫 CI 실행에서 이 지점을 먼저 확인하라 — 아래 마지막 검증 블록이 그때 단서를 남긴다.

set -eu

echo "=== ci_post_clone.sh 시작 ==="
echo "작업 디렉터리(스크립트 기준): $(pwd)"
echo "CI_XCODE_CLOUD=${CI_XCODE_CLOUD:-<없음>}"
echo "CI_BRANCH=${CI_BRANCH:-<없음>}  CI_WORKFLOW=${CI_WORKFLOW:-<없음>}"
echo "CI_XCODEBUILD_ACTION=${CI_XCODEBUILD_ACTION:-<없음>}"

# ---------------------------------------------------------------------------
# 1. 저장소 루트로 이동
#
# Xcode Cloud에서는 `CI_PRIMARY_REPOSITORY_PATH`가 clone된 소스 위치다.
# 로컬에서 이 스크립트를 그대로 흉내 낼 수 있게 폴백을 둔다 — 그래야 CI에 올리기 전에
# 여기서 터질지 알 수 있다.
# ---------------------------------------------------------------------------
REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"
if [ ! -f "$REPO_ROOT/project.yml" ]; then
    echo "실패: 저장소 루트를 못 찾았다. project.yml이 없다: $REPO_ROOT" >&2
    exit 1
fi
cd "$REPO_ROOT"
echo "저장소 루트: $(pwd)"

# ---------------------------------------------------------------------------
# 2. GoogleService-Info.plist — 환경 변수 주입 경로 (선택지 나)
#
# 저장소에 커밋하는 쪽(선택지 가)을 택했다면 파일이 이미 있으므로 이 블록은 건너뛴다.
# 커밋하지 않는 쪽을 택했다면 App Store Connect의 **비밀 환경 변수**
# `GOOGLE_SERVICE_INFO_PLIST_BASE64`에 base64 값을 넣어 두어야 한다.
#
# 둘 다 없으면 **여기서 실패시킨다.** 없는 채로 빌드하면 `FirebaseApp.configure()`가
# 런타임에 터지는데, 그건 CI 로그가 아니라 TestFlight 사용자에게 가서야 드러난다.
# ---------------------------------------------------------------------------
PLIST_PATH="App/GoogleService-Info.plist"
if [ -f "$PLIST_PATH" ]; then
    echo "GoogleService-Info.plist: 저장소에 있음 ($(wc -c < "$PLIST_PATH" | tr -d ' ') bytes)"
elif [ -n "${GOOGLE_SERVICE_INFO_PLIST_BASE64:-}" ]; then
    echo "GoogleService-Info.plist: 환경 변수에서 복원한다"
    printf '%s' "$GOOGLE_SERVICE_INFO_PLIST_BASE64" | base64 --decode > "$PLIST_PATH"
    # 복원이 실제로 쓸 수 있는 plist인지 확인한다. base64가 잘리면 여기서 걸린다.
    if ! plutil -lint "$PLIST_PATH" > /dev/null 2>&1; then
        echo "실패: 복원한 GoogleService-Info.plist가 올바른 plist가 아니다." >&2
        echo "      비밀 환경 변수 GOOGLE_SERVICE_INFO_PLIST_BASE64 값이 잘렸는지 확인하라." >&2
        exit 1
    fi
    # **값은 절대 로그로 내보내지 않는다.** 키가 들어 있다. 크기만 남긴다.
    echo "GoogleService-Info.plist: 복원 완료 ($(wc -c < "$PLIST_PATH" | tr -d ' ') bytes)"
else
    echo "실패: GoogleService-Info.plist가 없고 GOOGLE_SERVICE_INFO_PLIST_BASE64도 비어 있다." >&2
    echo "      둘 중 하나가 반드시 있어야 한다 — docs/release/xcode-cloud-setup.md 2절 참조." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 3. 서명 팀 — Xcode Cloud가 `CI_TEAM_ID`로 알려 준다
#
# `project.yml:13`의 `DEVELOPMENT_TEAM`은 로컬에서 빈 문자열이다(팀 ID를 저장소에 두지 않는다).
# CI에서는 환경 변수 값으로 채워 넣는다 — 저장소를 고치지 않고도 서명이 선다.
# 값이 없으면 **막지 않는다.** Xcode Cloud가 서명을 스스로 관리하는 구성일 수 있어서,
# 여기서 실패시키면 멀쩡한 빌드를 막게 된다. 대신 로그에 크게 남긴다.
# ---------------------------------------------------------------------------
if [ -n "${CI_TEAM_ID:-}" ]; then
    echo "DEVELOPMENT_TEAM: CI_TEAM_ID로 채운다"
    /usr/bin/sed -i '' "s/DEVELOPMENT_TEAM: \"\"/DEVELOPMENT_TEAM: \"$CI_TEAM_ID\"/" project.yml
    grep -n "DEVELOPMENT_TEAM" project.yml || true
else
    echo "주의: CI_TEAM_ID가 없다. project.yml의 DEVELOPMENT_TEAM이 빈 값 그대로다."
    echo "      서명 단계에서 실패하면 이 줄을 먼저 의심하라."
fi

# ---------------------------------------------------------------------------
# 4. XcodeGen 설치
#
# `sudo`를 쓸 수 없으므로 Homebrew를 그대로 쓴다(Xcode Cloud 이미지에 이미 있다).
# 이미 있으면 설치를 건너뛴다 — 재실행이 싸야 디버깅이 편하다.
# ---------------------------------------------------------------------------
if command -v xcodegen > /dev/null 2>&1; then
    echo "XcodeGen: 이미 있음"
else
    echo "XcodeGen: brew로 설치한다"
    if ! command -v brew > /dev/null 2>&1; then
        echo "실패: brew가 없다. Xcode Cloud 이미지가 바뀌었는지 확인하라." >&2
        exit 1
    fi
    # 설치 로그는 길다. 실패했을 때만 의미가 있으므로 그대로 흘려보낸다.
    brew install xcodegen
fi
echo "XcodeGen 버전: $(xcodegen --version)"

# ---------------------------------------------------------------------------
# 5. 프로젝트 생성
# ---------------------------------------------------------------------------
echo "=== xcodegen generate ==="
xcodegen generate

if [ ! -d "Tadak.xcodeproj" ]; then
    echo "실패: xcodegen이 끝났는데 Tadak.xcodeproj가 없다." >&2
    exit 1
fi
echo "Tadak.xcodeproj 생성됨"

# ---------------------------------------------------------------------------
# 5-1. Package.resolved 를 제자리로 복사한다
#
# Xcode Cloud 는 **자동 의존성 해석이 꺼져 있다** — 이 파일이 없으면 이렇게 죽는다:
#   "Could not resolve package dependencies: a resolved file is required when
#    automatic dependency resolution is disabled and should be placed at
#    .../Tadak.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
# (2026-09-16 실측 — 첫 CI 빌드가 정확히 여기서 멈췄다.)
#
# 그 경로는 `Tadak.xcodeproj` 안이라 생성물과 함께 사라진다. 그래서 **저장소 루트가 SSOT**이고
# (`.gitignore` 의 `!/Package.resolved`) 여기서 xcodegen 이 만든 자리로 옮겨 놓는다.
# **반드시 xcodegen 뒤여야 한다** — 앞에 두면 생성 과정에서 덮여 사라진다.
# ---------------------------------------------------------------------------
SWIFTPM_DIR="Tadak.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
if [ -f "Package.resolved" ]; then
    mkdir -p "$SWIFTPM_DIR"
    cp Package.resolved "$SWIFTPM_DIR/Package.resolved"
    echo "Package.resolved: 제자리로 복사했다 ($SWIFTPM_DIR)"
    # 무엇이 고정됐는지 로그에 남긴다 — 배포본과 우리가 검증한 버전이 같은지 나중에 대조할 수 있다.
    /usr/bin/grep -E '"(identity|version)"' Package.resolved | /usr/bin/paste - - | /usr/bin/sed 's/^/  /' || true
else
    echo "실패: 저장소 루트에 Package.resolved 가 없다." >&2
    echo "      Xcode Cloud 는 자동 의존성 해석이 꺼져 있어 이 파일이 반드시 필요하다." >&2
    echo "      로컬에서 xcodegen generate 후 빌드해 만들고, 루트로 복사해 커밋하라:" >&2
    echo "      cp $SWIFTPM_DIR/Package.resolved Package.resolved" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 6. 빌드 전에 깨질 것들을 여기서 미리 잡는다
#
# CI 로그가 유일한 단서다. `xcodebuild`가 엉뚱한 에러로 터지기 전에 원인을 먼저 남긴다.
# ---------------------------------------------------------------------------
echo "=== 사전 점검 ==="

# 6-1. Crashlytics dSYM 업로드 스크립트 — `project.yml`의 postBuildScripts가 부른다.
#      저장소에 없으면 빌드가 그 단계에서 실패한다.
for f in tools/firebase-crashlytics-run tools/upload-symbols; do
    if [ -f "$f" ]; then
        echo "  OK  $f ($(wc -c < "$f" | tr -d ' ') bytes, 실행권한: $([ -x "$f" ] && echo 있음 || echo 없음))"
    else
        echo "  실패: $f 가 저장소에 없다." >&2
        echo "        .gitignore의 /tools/* negation이 실제로 커밋됐는지 확인하라" >&2
        echo "        (로컬 .git/info/exclude가 막고 있으면 git add -f 가 필요하다)." >&2
        exit 1
    fi
done

# 6-2. 수집 선언 정합 — 프라이버시 선언과 실제 동작이 어긋난 채 배포되는 것을 막는다.
#      2026-09-14 전면 개정. 옛 블록은 "매니페스트는 수집 안 함인데 SDK는 수집을 켠 채로 나간다"를
#      전제로 FIREBASE_ANALYTICS_COLLECTION_ENABLED 키가 **있는지**를 물었다. 그 전제가 뒤집혔다 —
#      사용자 결정(2026-09-14)으로 수집을 켜고 가며, 매니페스트가 이제 수집을 **선언한다**(6종).
#      그러므로 지금 지켜야 할 불변식은 정반대다. 세 가지를 본다.
COLLECTION_GATE_FAIL=0

#  (1) 수집 차단 키는 **없어야** 한다. 있으면 기본값이 끔으로 뒤집혀,
#      "기본값은 둘 다 켜짐"이라고 공표한 처리방침과 앱이 어긋난다.
for KEY in FIREBASE_ANALYTICS_COLLECTION_ENABLED FirebaseDataCollectionDefaultEnabled \
           FirebaseCrashlyticsCollectionEnabled; do
    if /usr/libexec/PlistBuddy -c "Print :$KEY" App/Info.plist > /dev/null 2>&1; then
        echo "  실패: App/Info.plist에 $KEY 가 있다." >&2
        echo "        이 키가 있으면 수집 기본값이 끔으로 뒤집힌다. 처리방침은 '기본값 켜짐'으로 공표돼 있다." >&2
        echo "        의도한 변경이면 처리방침·앱 문구·store-metadata를 함께 고치고 이 게이트를 다시 써라." >&2
        COLLECTION_GATE_FAIL=1
    fi
done
[ "$COLLECTION_GATE_FAIL" = "0" ] && echo "  OK  수집 차단 키 없음 (기본 켬 — 처리방침과 일치)"

#  (2) 앱 매니페스트는 수집을 **선언해야** 한다. 실제로 수집하므로 빈 선언은 거짓이다.
APP_TYPES=$(/usr/libexec/PlistBuddy -c "Print :NSPrivacyCollectedDataTypes" App/PrivacyInfo.xcprivacy 2>/dev/null \
            | grep -cE '^[[:space:]]*NSPrivacyCollectedDataType = ' || true)
if [ "${APP_TYPES:-0}" -lt 1 ]; then
    echo "  실패: App/PrivacyInfo.xcprivacy가 수집을 하나도 선언하지 않는다." >&2
    echo "        Firebase Analytics·Crashlytics가 링크돼 있는데 '수집 안 함'으로 제출하는 상태다." >&2
    COLLECTION_GATE_FAIL=1
else
    echo "  OK  앱 매니페스트 수집 선언 $APP_TYPES 종"
fi

#  (3) 키보드 익스텐션 매니페스트는 수집이 **0이어야** 한다.
#      익스텐션에는 어떤 네트워크 SDK도 링크하지 않는다(.claude/rules/security.md 1순위).
EXT_TYPES=$(/usr/libexec/PlistBuddy -c "Print :NSPrivacyCollectedDataTypes" Keyboard/PrivacyInfo.xcprivacy 2>/dev/null \
            | grep -cE '^[[:space:]]*NSPrivacyCollectedDataType = ' || true)
if [ "${EXT_TYPES:-0}" -ne 0 ]; then
    echo "  실패: Keyboard/PrivacyInfo.xcprivacy가 수집을 $EXT_TYPES 종 선언한다. 0이어야 한다." >&2
    COLLECTION_GATE_FAIL=1
else
    echo "  OK  익스텐션 매니페스트 수집 선언 0종"
fi

if [ "$COLLECTION_GATE_FAIL" = "1" ]; then
    echo "  수집 선언 정합 게이트 실패 — 배포를 멈춘다." >&2
    exit 1
fi

echo "=== ci_post_clone.sh 정상 종료 ==="
exit 0
