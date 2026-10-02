import SwiftUI
import Testing
import TadakDomain
import KeyboardCore
@testable import KeyboardUI

/// 화면 연결 — `KeyboardLayoutView`(키 폭을 정하는 `rowView`가 사는 곳)를 **실제로 그려** 키의 왼쪽 경계를 픽셀로 잰다.
///
/// 왜 따로 있나(3차 개정, 반론자2 변이 M2): 계산 함수 테스트(`ColumnAlignmentTests`)는 화면이 그 함수를 **쓰는지**를 모른다 —
/// `rowView`가 정렬을 끄도록 바꿔도 KeyboardUI 57/57이 녹색이었고, 그 사이 숫자 `0`이 다시 오른쪽으로 밀렸다.
/// 여기서는 `ImageRenderer`로 뷰를 그리고(2배율) 검은 배경 → 키 색으로 바뀌는 x를 행마다 읽어, 아래 행 키가 위 행 열에 서는지 본다.
///
/// **한계**: macOS에서 SwiftUI가 그린 그림이다 — iOS 기기의 픽셀 반올림·글꼴·터치 영역을 재는 것이 아니다. 지구본은 UIKit 버튼이라
/// 여기서는 빈 칸으로 그려진다(자리는 차지한다). 기기 화면 확인은 실기 몫으로 남는다(설계서 0-3절).
@MainActor
@Suite("자판 행 — 그린 화면의 열 정렬(화면 연결)")
struct KeyboardRowRenderTests {

    /// 배경 검정 · 문자 키 빨강 · 기능 키 초록 · 글자 파랑 — 경계는 「거의 검정 → 아닌 것」으로만 읽는다(글자는 키 안에 있다)
    private let spec = ThemeSpec(
        id: "render-probe", displayName: "render-probe",
        light: .init(keyboardBackground: "#000000", characterKey: "#FF0000",
                     functionKey: "#00FF00", keyText: "#0000FF", accent: "#007AFF"),
        dark: .init(keyboardBackground: "#000000", characterKey: "#FF0000",
                    functionKey: "#00FF00", keyText: "#0000FF", accent: "#007AFF"))
    private let scale: CGFloat = 2
    private let height: CGFloat = 216
    /// 아이폰 SE(375)·17 Pro(402)·Pro Max(440)에서 좌우 여백 6을 뺀 자판 폭
    private let widths: [CGFloat] = [369, 396, 434]
    /// 2배율 픽셀 하나 반 — 정렬되면 같은 픽셀이고, 옛 식으로 되돌리면 3pt 넘게 벌어진다
    private let tolerance: CGFloat = 0.75

    private struct Rendered {
        let pixels: [UInt8]
        let pixelWidth: Int
        let pixelHeight: Int
    }

    private func render(_ layout: LayoutDefinition, globe: Bool, width: CGFloat) throws -> Rendered {
        let theme = ResolvedTheme(spec: spec, appearance: .light, systemColorScheme: .light)
        let state = KeyboardViewState(layout: layout, themeSpec: spec, showsKeyPreview: false,
                                      needsInputModeSwitchKey: globe)
        let view = KeyboardLayoutView(state: state, theme: theme, inputModeSwitchButton: nil, onEvent: { _ in })
            .frame(width: width, height: height)
            .background(Color.black)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let image = try #require(renderer.cgImage)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(CGContext(
            data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Rendered(pixels: pixels, pixelWidth: image.width, pixelHeight: image.height)
    }

    /// `row`번째 행(위에서부터) 가운데 높이에서, 배경 → 키로 바뀌는 x(pt)들
    private func leftEdges(_ image: Rendered, row: Int, rowCount: Int) -> [CGFloat] {
        let spacing = KeyboardMetrics.rowSpacing
        let rowHeight = (height - spacing * CGFloat(rowCount - 1)) / CGFloat(rowCount)
        let y = Int(((rowHeight + spacing) * CGFloat(row) + rowHeight / 2) * scale)
        var edges: [CGFloat] = []
        var inKey = false
        for x in 0..<image.pixelWidth {
            let i = (y * image.pixelWidth + x) * 4   // 비트맵 버퍼 첫 줄 = 그림 맨 위
            let isKey = max(image.pixels[i], image.pixels[i + 1], image.pixels[i + 2]) > 64
            if isKey && !inKey { edges.append(CGFloat(x) / scale) }
            inKey = isKey
        }
        return edges
    }

    private func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) <= tolerance }

    @Test("숫자 페이지 — 그린 화면에서 0이 2·5·8 열에, -+ 가 ⌫·⏎·.,*/ 열에 선다", arguments: [false, true])
    func numberPage(globe: Bool) throws {
        let layout = LayoutDefinition.layout(for: .keypadPad(page: 0), hangulLayout: .dubeolsik, inputModeSwitchKey: globe)
        for width in widths {
            let image = try render(layout, globe: globe, width: width)
            let top = leftEdges(image, row: 0, rowCount: 4)
            let bottom = leftEdges(image, row: 3, rowCount: 4)
            // 지구본은 빈 칸으로 그려져 경계가 없다 — 보이는 키는 [▶][가][0][␣][-+]
            try #require(top.count == 4 && bottom.count == 5, "폭 \(width): 위 \(top) / 아래 \(bottom)")
            #expect(close(bottom[2], top[1]), "폭 \(width) — 0 \(bottom[2]) vs 2 \(top[1])")
            #expect(close(bottom[4], top[3]), "폭 \(width) — -+ \(bottom[4]) vs ⌫ \(top[3])")
            for row in 1...2 {
                let middle = leftEdges(image, row: row, rowCount: 4)
                #expect(middle.count == 4 && zip(middle, top).allSatisfy { close($0, $1) }, "폭 \(width) 행 \(row)")
            }
        }
    }

    @Test("기호 페이지 — 그린 화면에서 4행 기능 키 경계가 위 행 열 경계와 같다", arguments: [false, true])
    func symbolPage(globe: Bool) throws {
        let layout = LayoutDefinition.layout(for: .keypadPad(page: 1), hangulLayout: .dubeolsik, inputModeSwitchKey: globe)
        for width in widths {
            let image = try render(layout, globe: globe, width: width)
            let top = leftEdges(image, row: 0, rowCount: 4)
            let bottom = leftEdges(image, row: 3, rowCount: 4)
            // 보이는 키: [페이지][가][(🌐 빈 칸)][␣][⌫][⏎] → 열 0, 1, 3 또는 2, 5, 6
            let columns = globe ? [0, 1, 3, 5, 6] : [0, 1, 2, 5, 6]
            try #require(top.count == 7 && bottom.count == columns.count, "폭 \(width): 위 \(top) / 아래 \(bottom)")
            for (edge, column) in zip(bottom, columns) {
                #expect(close(edge, top[column]), "폭 \(width) 열 \(column): \(edge) vs \(top[column])")
            }
        }
    }

    @Test("자동 숫자 패드(지구본 있음) — 그린 화면에서 0이 2 열에, ⌫가 3 열에")
    func numberPad() throws {
        let layout = LayoutDefinition.layout(for: .numberPad(.decimal), hangulLayout: .dubeolsik)
        for width in widths {
            let image = try render(layout, globe: true, width: width)
            let top = leftEdges(image, row: 0, rowCount: 4)
            let bottom = leftEdges(image, row: 3, rowCount: 4)
            // 보이는 키: [.½][(🌐½ 빈 칸)][0][⌫]
            try #require(top.count == 3 && bottom.count == 3, "폭 \(width): 위 \(top) / 아래 \(bottom)")
            #expect(close(bottom[1], top[1]), "폭 \(width) — 0 \(bottom[1]) vs 2 \(top[1])")
            #expect(close(bottom[2], top[2]), "폭 \(width) — ⌫ \(bottom[2]) vs 3 \(top[2])")
        }
    }
}
