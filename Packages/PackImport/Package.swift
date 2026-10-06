// swift-tools-version: 6.0
import PackageDescription

// 외부 채움글 팩 가져오기 — **앱 전용**(PDR `docs/design-reviews/external-snippet-packs.md` 2절·18절 1-a).
// CSV 파서·인코딩·헤더/메타·단축어 셀·문자 정리·템플릿 검증을 키보드 익스텐션 바이너리 밖에 둔다
// (파일 선택·가져오기는 컨테이너 앱에서만 한다 — 익스텐션은 변환본만 읽는다). 외부 의존성 0(R11).
// KeyboardCore는 템플릿의 성경 충돌 검사(`BibleReferenceParser`, 10-2)를 위해서만 쓴다.
// TadakData는 외부 채움글 **쓰기 쪽**(`PackStore`·세대 setter·내 채움글 저장, 1-b)이 읽기 쪽 부품(위치·세대 읽기·snapshot 로더)을
// 함께 쓰려고 의존한다 — 쓰기 코드는 이 앱 전용 모듈에만 있어 키보드 바이너리에 실리지 않는다(codex 반론 #11).
let package = Package(
    name: "PackImport",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PackImport", targets: ["PackImport"])
    ],
    dependencies: [
        .package(path: "../TadakDomain"),
        .package(path: "../KeyboardCore"),
        .package(path: "../TadakData")
    ],
    targets: [
        .target(
            name: "PackImport",
            dependencies: ["TadakDomain", "KeyboardCore", "TadakData"]
        ),
        .testTarget(
            name: "PackImportTests",
            dependencies: ["PackImport"],
            resources: [.copy("Fixtures")]
        )
    ]
)
