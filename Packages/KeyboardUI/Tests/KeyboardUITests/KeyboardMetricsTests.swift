import Testing
import CoreGraphics
import KeyboardCore
@testable import KeyboardUI

/// 폭 상한·목표 종횡비는 **KeyboardUI와 조립 지점이 함께 보는 값**이다.
/// 여기서 값을 고정해 두 곳이 갈라지는 회귀를 잡는다 (UX-8 — 검증자 실측 2026-09-09).
@Suite("KeyboardMetrics — 폭 상한과 목표 종횡비")
struct KeyboardMetricsTests {

    /// 아이폰 폭 범위 전체(320~440pt)가 모든 자판의 상한 아래여야 한다.
    /// 하나라도 걸리면 아이폰 레이아웃이 바뀐다 — 합의된 회귀 금지선이다.
    @Test("아이폰 폭에서는 어떤 자판도 폭 상한에 걸리지 않는다")
    func phoneWidthsNeverClamped() {
        for units in [3.0, 4.0, 8.0, 10.0] {
            let cap = KeyboardMetrics.contentMaxWidth(units: units)
            #expect(cap > 440, "열 수 \(units)의 상한 \(cap)pt가 아이폰 최대 폭 440pt 아래다")
        }
    }

    /// 10열은 지금까지의 900pt를 그대로 내야 한다 — 아이패드 세로(834pt)가 상한 아래로 남고
    /// 이미 합의된 세로 레이아웃이 보존된다.
    @Test("10열 자판의 상한은 900pt다 (아이패드 세로 834pt는 그 아래)")
    func tenColumnCapUnchanged() {
        let cap = KeyboardMetrics.contentMaxWidth(units: 10)
        #expect(abs(cap - 900) < 0.5)
        #expect(cap > 834, "아이패드 11인치 세로는 상한에 걸리지 않아야 한다")
    }

    /// UX-8의 본체: 열 수가 적은 자판일수록 폭을 더 좁게 잘라야 키가 납작해지지 않는다.
    @Test("열 수가 적을수록 자판이 좁아진다 (천지인 4열 < 단모음 8열 < 두벌식 10열)")
    func fewerColumnsGetNarrowerKeyboard() {
        let cheonjiin = KeyboardMetrics.contentMaxWidth(units: 4)
        let danmoeum = KeyboardMetrics.contentMaxWidth(units: 8)
        let dubeolsik = KeyboardMetrics.contentMaxWidth(units: 10)
        #expect(cheonjiin < danmoeum)
        #expect(danmoeum < dubeolsik)
    }

    /// 예전 버그: 10열 폭 상한(900pt)만 두면 천지인 키가 (900-6-15)/4 = 219.75pt로
    /// 종횡비 2.98:1이 된다 — 상한 전(2.95:1)과 사실상 같다. 열 수를 반영해야 닫힌다.
    @Test("상한 폭에서 모든 자판의 키 종횡비가 목표 안에 든다")
    func keyAspectStaysWithinTargetAtCap() {
        for units in [3.0, 4.0, 8.0, 10.0] {
            let cap = KeyboardMetrics.contentMaxWidth(units: units)
            let keyWidth = KeyboardMetrics.keyWidth(availableWidth: cap, units: units)
            let rowHeight = keyWidth / KeyboardMetrics.targetKeyAspect(units: units)
            #expect(abs(rowHeight - KeyboardMetrics.targetRowHeight) < 0.5,
                    "열 수 \(units): 행 높이 \(rowHeight)pt")
            // 상한에서의 종횡비는 곧 목표 종횡비이고, 그것은 아이폰 값을 넘지 않는다.
            // (숫자 패드 3열은 아이폰에서도 2.58:1이다 — 그 자판은 원래 납작하다.
            //  규칙은 "아이패드에서 더 납작해지지 않는다"이지 "정사각으로 만든다"가 아니다.)
            let aspect = keyWidth / rowHeight
            let phoneAspect = KeyboardMetrics.keyWidth(
                availableWidth: KeyboardMetrics.phoneReferenceWidth, units: units)
                / KeyboardMetrics.phoneRowHeight
            #expect(aspect <= max(phoneAspect, KeyboardMetrics.baseKeyAspect) + 0.01,
                    "열 수 \(units): 아이패드 \(aspect):1 vs 아이폰 \(phoneAspect):1")
        }
    }

    /// "아이패드에서 키가 아이폰에서보다 더 납작해지지 않는다" — 이 규칙의 직접 검사.
    @Test("목표 종횡비는 아이폰에서의 종횡비보다 납작하지 않다")
    func targetNeverFlatterThanPhone() {
        for units in [3.0, 4.0, 8.0, 10.0] {
            let phoneKey = KeyboardMetrics.keyWidth(
                availableWidth: KeyboardMetrics.phoneReferenceWidth, units: units)
            let phoneAspect = phoneKey / KeyboardMetrics.phoneRowHeight
            #expect(KeyboardMetrics.targetKeyAspect(units: units) >= min(phoneAspect, 100),
                    "열 수 \(units): 아이폰 \(phoneAspect):1")
        }
        // 두벌식은 아이폰에서 세로로 긴 키(0.72:1)다 — 아이패드에서 더 세로로 만들지는 않는다
        #expect(KeyboardMetrics.targetKeyAspect(units: 10) == KeyboardMetrics.baseKeyAspect)
    }

    /// 검증자 실측 회귀 고정: 10열 상한(900pt)만 있던 시절 천지인은 219.75pt 키에 2.98:1이었다.
    @Test("천지인은 10열 상한(900pt)이 아니라 자기 열 수의 상한을 받는다")
    func cheonjiinNoLongerUsesTenColumnCap() {
        let cap = KeyboardMetrics.contentMaxWidth(units: 4)
        #expect(cap < 700, "천지인 상한 \(cap)pt — 900pt 그대로면 2.98:1이 된다")
        let keyAtOldCap = KeyboardMetrics.keyWidth(availableWidth: 900, units: 4)
        #expect(abs(keyAtOldCap - 219.75) < 0.5, "옛 동작 재현 확인용 — 이 값이 문제였다")
        let keyNow = KeyboardMetrics.keyWidth(availableWidth: cap, units: 4)
        #expect(keyNow < keyAtOldCap)
    }

    // MARK: - 도구 행 (REQ-4)

    /// 아이폰 도구 행은 지금 모습 그대로여야 한다 — 합의된 레이아웃이다.
    /// 아이폰에서 나오는 버튼 폭(폭 320~440pt · 도구 4~5개)이 전부 상한 아래인지 단정한다.
    @Test("아이폰에서는 도구 버튼 폭 상한에 걸리지 않는다")
    func toolRowUnclampedOnPhone() {
        let toolbarPadding: CGFloat = 20  // KeyboardRootView의 .padding(.horizontal, 10)
        for screenWidth in [320.0, 375.0, 393.0, 402.0, 440.0] as [CGFloat] {
            for count in [4, 5] {
                let available = screenWidth - toolbarPadding
                    - CGFloat(count - 1) * KeyboardMetrics.toolButtonSpacing
                let evenWidth = available / CGFloat(count)
                #expect(evenWidth < KeyboardMetrics.maxToolButtonWidth,
                        "폭 \(screenWidth)pt · 도구 \(count)개 → 버튼 \(evenWidth)pt")
                // 상한 폭이 실제 가용 폭보다 크므로 프레임이 아무 일도 하지 않는다
                #expect(KeyboardMetrics.toolRowMaxWidth(count: count) > screenWidth - toolbarPadding)
            }
        }
    }

    /// 아이패드 가로(자판 폭 894pt)에서는 상한이 실제로 걸려야 한다 — 그게 REQ-4의 목적이다.
    @Test("아이패드 가로에서는 도구 행이 상한에 걸려 가운데로 모인다")
    func toolRowClampedOnWideKeyboard() {
        let available: CGFloat = 894 - 20   // 자판 폭 안의 툴바 가용 폭
        for count in [4, 5] {
            let cap = KeyboardMetrics.toolRowMaxWidth(count: count)
            #expect(cap < available, "도구 \(count)개 상한 \(cap)pt가 가용 \(available)pt보다 작아야 한다")
        }
        // 도구 5개일 때 버튼 중심 간격 = 버튼 폭 + 간격 = 110pt (수정 전 178pt)
        #expect(KeyboardMetrics.maxToolButtonWidth + KeyboardMetrics.toolButtonSpacing == 110)
    }

    /// 조립 지점은 배열에서 곧바로 상한을 얻는다. 배열 → 열 수 → 상한 경로가 이어지는지 본다.
    @Test("배열에서 곧바로 상한을 낸다 — 천지인이 두벌식보다 좁다")
    func capFromLayout() {
        let cheonjiin = KeyboardMetrics.contentMaxWidth(for: .cheonjiin)
        let dubeolsik = KeyboardMetrics.contentMaxWidth(for: .dubeolsik)
        let danmoeum = KeyboardMetrics.contentMaxWidth(for: .danmoeum)
        #expect(cheonjiin < danmoeum)
        #expect(danmoeum < dubeolsik)
        #expect(abs(dubeolsik - 900) < 0.5)
    }
}

/// 확대 미리보기 크기 (REQ-5) — 아이폰 회귀 금지선을 단정문으로 박는다.
@Suite("확대 미리보기 크기")
struct KeyPreviewSizeTests {

    /// 아이폰 문자 키는 가장 넓은 기기(440pt)에서도 38.9pt다. 전부 상수(46 x 52)여야 한다.
    @Test("아이폰 키 크기에서는 미리보기가 46 x 52 그대로다")
    func phoneUnchanged() {
        for screenWidth in [320.0, 375.0, 393.0, 402.0, 440.0] as [CGFloat] {
            let keyWidth = KeyboardMetrics.keyWidth(availableWidth: screenWidth, units: 10)
            // 높이 배율 80~120%까지 훑는다 — 배율을 올려도 폭은 그대로라 상수가 이긴다
            for scale in [0.8, 1.0, 1.2] as [CGFloat] {
                let size = KeyCapView.previewSize(
                    keySize: CGSize(width: keyWidth, height: 48.75 * scale))
                #expect(size.width == 46 && size.height == 52,
                        "폭 \(screenWidth) · 키 \(keyWidth)pt → \(size)")
            }
        }
    }

    /// 아이패드에서는 미리보기가 **키보다 커야** 한다 — '확대 미리보기'라는 이름대로.
    /// 수정 전에는 46 x 52 상수라 키(78 x 69)보다 작았다 (검증자 실측 REQ-5).
    @Test("아이패드 키 크기에서는 미리보기가 키보다 크다")
    func padPreviewIsLargerThanKey() {
        for key in [CGSize(width: 77, height: 68),    // 11인치 세로 두벌식
                    CGSize(width: 86, height: 68),    // 두벌식 2행(9열)
                    CGSize(width: 85, height: 75)] {  // 가로
            let size = KeyCapView.previewSize(keySize: key)
            #expect(size.width > key.width, "키 \(key) → 미리보기 \(size)")
            #expect(size.height > key.height, "키 \(key) → 미리보기 \(size)")
        }
    }

    /// 천지인(140pt 키)에서 미리보기가 과하게 커지지 않게 증가폭을 묶는다.
    @Test("아주 넓은 키에서는 증가폭이 +30pt로 묶인다")
    func veryWideKeyIsCapped() {
        let key = CGSize(width: 140.5, height: 75)
        let size = KeyCapView.previewSize(keySize: key)
        #expect(size.width == key.width + 30)
    }
}

/// 패널 목록 행 높이 (UX-10) — 아이폰 회귀 금지선.
@Suite("패널 목록 행 높이")
struct ListRowMinHeightTests {

    @Test("아이폰 패널 폭에서는 36pt 그대로다")
    func phoneUnchanged() {
        for screenWidth in [320.0, 375.0, 393.0, 402.0, 440.0] as [CGFloat] {
            let panel = screenWidth - 6   // KeyboardRootView의 .padding(.horizontal, 3)
            #expect(KeyboardMetrics.listRowMinHeight(panelWidth: panel) == 36,
                    "폭 \(screenWidth) · 패널 \(panel)pt")
        }
    }

    /// 아이패드에서 가장 좁은 자판(천지인 584pt)에서도 올라가야 한다.
    @Test("아이패드 패널 폭에서는 HIG 최소 44pt로 올라간다")
    func padMeetsHIG() {
        for contentWidth in [KeyboardMetrics.contentMaxWidth(units: 4),   // 천지인 584pt
                             KeyboardMetrics.contentMaxWidth(units: 8),   // 단모음 720pt
                             KeyboardMetrics.contentMaxWidth(units: 10)] { // 두벌식 900pt
            let panel = contentWidth - 6
            #expect(KeyboardMetrics.listRowMinHeight(panelWidth: panel) == 44,
                    "패널 \(panel)pt")
        }
    }
}
