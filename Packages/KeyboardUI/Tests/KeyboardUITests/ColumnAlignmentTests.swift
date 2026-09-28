import Foundation
import Testing
import KeyboardCore
@testable import KeyboardUI

/// 열 정렬 — 숫자 페이지 4행의 `0`이 위 `2 5 8`보다 간격 하나(5pt)만큼 오른쪽으로 밀리던 버그(사장님 폰 세션 4-1 2차,
/// 2026-09-28). 원인은 **행마다** `간격 × (키 수 − 1)`을 먼저 빼고 남은 폭을 비율로 나누던 계산이다 — 반 칸 둘로 시작하는
/// 행은 간격이 하나 더 있어 뒤 키가 전부 밀린다. `KeyboardMetrics.keyWidths(units:totalWidth:alignsColumns:)`가 고정한다.
@Suite("자판 행 — 열 정렬")
struct ColumnAlignmentTests {

    private let spacing = KeyboardMetrics.keySpacing
    /// 아이폰 SE(375)·17 Pro(402)·Pro Max(440) 폭에서 좌우 여백을 뺀 값 + 아이패드 한 폭
    private let widths: [CGFloat] = [369, 396, 434, 828]

    private func units(_ row: [LayoutDefinition.Key]) -> [Double] { row.map(\.width) }

    /// 키 폭 → 각 키의 왼쪽 x (HStack(spacing:)이 놓는 그대로)
    private func lefts(_ keyWidths: [CGFloat]) -> [CGFloat] {
        var x: CGFloat = 0
        return keyWidths.map { width in
            defer { x += width + spacing }
            return x
        }
    }

    private func rowLefts(_ layout: LayoutDefinition, _ row: Int, width: CGFloat) -> [CGFloat] {
        lefts(KeyboardMetrics.keyWidths(units: units(layout.rows[row]), totalWidth: width,
                                        alignsColumns: layout.alignsColumns))
    }

    private func keypad(_ page: Int, globe: Bool) -> LayoutDefinition {
        LayoutDefinition.layout(for: .keypadPad(page: page), hangulLayout: .dubeolsik, inputModeSwitchKey: globe)
    }

    @Test("숫자 페이지 4행 — 0의 왼쪽 == 위 행 두 번째 키(2·5·8)의 왼쪽, 오른쪽 키들도 위 열에 맞물린다", arguments: [true, false])
    func numberPageZeroAligned(globe: Bool) {
        let layout = keypad(0, globe: globe)
        for width in widths {
            let top = rowLefts(layout, 0, width: width)
            let bottom = rowLefts(layout, 3, width: width)
            // 4행: [▶½][가½][0][(🌐½)][␣(½ 또는 1)][+-]
            #expect(abs(bottom[2] - top[1]) < 0.01, "폭 \(width) — 0이 2·5·8 열에서 벗어났다: \(bottom[2]) vs \(top[1])")
            #expect(abs(bottom[3] - top[2]) < 0.01, "폭 \(width) — 9 밑 칸(지구본 또는 스페이스)의 왼쪽")
            #expect(abs(bottom.last! - top[3]) < 0.01, "폭 \(width) — +- 는 ⌫·⏎·.,*/ 열")
            for row in 1...2 {
                #expect(zip(rowLefts(layout, row, width: width), top).allSatisfy { abs($0 - $1) < 0.01 })
            }
        }
    }

    @Test("기호 페이지 4행 — 기능 키 경계가 위 행 열 경계와 같은 x", arguments: [true, false])
    func symbolPageBoundaries(globe: Bool) {
        let layout = keypad(1, globe: globe)
        for width in widths {
            let top = rowLefts(layout, 0, width: width)          // 7열
            let bottom = rowLefts(layout, 3, width: width)
            // 4행 단위 경계: [페이지 1][가 1][(🌐 1)][␣ 2 또는 3][⌫ 1][⏎ 1] → 0,1,2,(3),5,6
            let expectedColumns = globe ? [0, 1, 2, 3, 5, 6] : [0, 1, 2, 5, 6]
            for (key, column) in zip(bottom, expectedColumns) {
                #expect(abs(key - top[column]) < 0.01, "폭 \(width) 열 \(column)")
            }
        }
    }

    @Test("자동 숫자 패드(지구본 있음) — 0의 왼쪽 == 2의 왼쪽, ⌫ == 3")
    func numberPadZeroAligned() {
        for kind in [NumberPadKind.plain, .decimal, .phone] {
            let layout = LayoutDefinition.layout(for: .numberPad(kind), hangulLayout: .dubeolsik)
            #expect(layout.rows[3].map(\.id).contains("globe"), "전제 — 보조·지구본 반 칸 둘로 시작한다")
            for width in widths {
                let top = rowLefts(layout, 0, width: width)
                let bottom = rowLefts(layout, 3, width: width)
                #expect(abs(bottom[2] - top[1]) < 0.01, "\(kind) 폭 \(width)")
                #expect(abs(bottom[3] - top[2]) < 0.01, "\(kind) 폭 \(width)")
            }
        }
    }

    @Test("정렬해도 행 전체 폭은 그대로 W — 키 폭 합 + 간격 합")
    func alignedRowFillsWidth() {
        for page in 0..<4 {
            let layout = keypad(page, globe: true)
            for row in layout.rows {
                for width in widths {
                    let keys = KeyboardMetrics.keyWidths(units: units(row), totalWidth: width, alignsColumns: true)
                    let total = keys.reduce(0, +) + spacing * CGFloat(keys.count - 1)
                    #expect(abs(total - width) < 0.01)
                }
            }
        }
    }

    /// ★ 다른 자판은 한 픽셀도 바뀌면 안 된다 — 옛 식(행마다 간격을 먼저 빼고 비율로 나눈다) 그대로
    @Test("열 정렬이 꺼진 자판(두벌식 하단 행 등)은 옛 계산과 같은 폭")
    func unalignedMatchesLegacy() {
        let layouts: [LayoutDefinition] = [.dubeolsik, .qwerty, .danmoeum, .cheonjiin, .symbols, .symbolsAlternate]
        for layout in layouts {
            #expect(!layout.alignsColumns)
            for row in layout.rows {
                for width in widths {
                    let total = row.reduce(0) { $0 + $1.width }
                    let available = width - spacing * CGFloat(row.count - 1)
                    let legacy = row.map { available * CGFloat($0.width) / CGFloat(total) }
                    let now = KeyboardMetrics.keyWidths(units: units(row), totalWidth: width, alignsColumns: false)
                    #expect(now == legacy)
                }
            }
        }
    }

    @Test("첫 패스 폭 0 — 어느 방식이든 음수 폭을 내지 않는다", arguments: [true, false])
    func zeroWidthNeverNegative(aligned: Bool) {
        for layout in [keypad(0, globe: true), .dubeolsik] {
            for row in layout.rows {
                let keys = KeyboardMetrics.keyWidths(units: units(row), totalWidth: 0, alignsColumns: aligned)
                #expect(keys.allSatisfy { $0 >= 0 && $0.isFinite })
            }
        }
    }
}
