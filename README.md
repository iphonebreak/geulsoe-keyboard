# 글쇠 (Geulsoe)

iOS 한글 커스텀 키보드. 두벌식·천지인·단모음 세 자판과 영어 쿼티를 지원하고, 키보드 상단 툴바에서
채움글(트리거 문구 → 전문 자동완성), 추천단어, 인증번호 붙여넣기, 클립보드 기록, 이모지를 쓸 수 있다.

- Swift 6 / SwiftUI, 최소 iOS 17. 키보드 익스텐션 + 설정 앱.
- **키보드가 입력한 내용을 수집·저장·전송하지 않는다.** 키보드 익스텐션에는 네트워크 코드가 없다
  (`Keyboard/`·`Packages/KeyboardCore`·`Packages/KeyboardUI`에 어떤 네트워크 SDK도 링크하지 않는다).
- 설정 앱에는 Firebase Analytics·Crashlytics가 있다(2026-09-14 도입). 앱 사용 통계와 크래시만
  보내고, **입력한 텍스트·클립보드·학습 단어는 대상이 아니다** — 그 경로가 생기지 않도록
  `.claude/hooks/telemetry-gate.sh`가 빌드 검사에서 막는다.
- 학습 단어·클립보드 기록은 App Group 안(기기 내)에만 남고 설정에서 끄면 즉시 삭제된다.

## 구조

```
App/         설정 앱 (온보딩 · 자판/툴바/화면/정보 탭 · 채움글 안내 애니메이션)
Keyboard/    키보드 익스텐션 (KeyboardViewController — 조립 지점)
Packages/    로컬 SPM — 의존성은 안쪽으로만
  HangulEngine/   한글 오토마타 (자판별 JamoSource + 공통 HangulAutomaton)
  TadakDomain/    설정·테마·채움글 엔티티, 저장소 프로토콜
  TadakData/      App Group·번들 리소스 저장소 (테마 JSON, 성경 bible.tdb, 사전 words.tdw)
  KeyboardCore/   입력 오케스트레이션 (InputController, LayoutDefinition, SnippetMatcher)
  KeyboardUI/     SwiftUI 자판·툴바
project.yml  XcodeGen 매니페스트 (Tadak.xcodeproj는 생성물)
```

번들 ID와 타깃·패키지 이름의 `Tadak`은 앱의 이전 이름(타닥)에서 왔다. 표시 이름만 글쇠다.

## 빌드

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project Tadak.xcodeproj -scheme Tadak \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# 엔진·패키지 단위 테스트 (수 초)
swift test --package-path Packages/HangulEngine
swift test --package-path Packages/KeyboardCore
```

실기에서는 설정 > 일반 > 키보드 > 키보드 추가에서 글쇠를 켠다. 클립보드·진동은 "전체 접근 허용"이 필요하다.

## 데이터 출처

- 성경 본문: 개역한글판(1961) — 저작재산권 보호기간 만료(2011-12-31). 권리자(대한성서공회)가
  [공개 확인](https://www.bskorea.or.kr/bbs/content.php?co_id=subpage2_3_4_1)한 사실이다.
  성명표시권·동일성유지권은 남으므로 본문을 변경·절삭하지 않는다.
  데이터 출처는 같은 모노레포의 `LifeBible_flutter/assets/hive/life_bible.hive`
  (2026-09-15 채택 — 1961년 당시 표기 「세째·네째」를 유지하는 판). 변환: `tools/convert_bible.py`
- 국가 상징문: 애국가·국기에 대한 맹세·대한민국 헌법(법제처 국가법령정보센터)·기미독립선언서 서두
- 추천단어 사전: [FrequencyWords](https://github.com/hermitdave/FrequencyWords) ko_50k 파생.
  파생물 `words.tdw` 는 **CC BY-SA 4.0 으로 배포한다** — 전문·개변 내역은
  [`Packages/TadakData/Sources/TadakData/Resources/LICENSE-words.md`](Packages/TadakData/Sources/TadakData/Resources/LICENSE-words.md)
