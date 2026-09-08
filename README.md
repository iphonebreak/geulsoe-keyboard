# 글쇠 (Geulsoe)

iOS 한글 커스텀 키보드. 두벌식·천지인·단모음 세 자판과 영어 쿼티를 지원하고, 키보드 상단 툴바에서
채움글(트리거 문구 → 전문 자동완성), 추천단어, 인증번호 붙여넣기, 클립보드 기록, 이모지를 쓸 수 있다.

- Swift 6 / SwiftUI, 최소 iOS 17. 키보드 익스텐션 + 설정 앱.
- 입력한 내용을 수집·저장·전송하지 않는다. 네트워크 코드가 없다. (`.claude/rules/security.md`)
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
docs/        설계 리뷰(PDR)·검증 절차 — 진입점 docs/README.md
tools/       데이터 변환·아이콘·클릭음 생성 스크립트
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

- 성경 본문: 개역한글판(1961) — 저작권 보호 기간 만료
- 국가 상징문: 애국가·국기에 대한 맹세·대한민국 헌법(법제처 국가법령정보센터)·기미독립선언서 서두
- 추천단어 사전: [FrequencyWords](https://github.com/hermitdave/FrequencyWords) ko_50k 파생 (CC-BY-SA-4.0)

자세한 설계 결정은 `docs/design-reviews/`에 있다.
