import Foundation
import Testing
@testable import PackImport

/// 인코딩 판정 (PDR `external-snippet-packs.md` 5-3b · R4 · R18, AC-17 · AC-18).
///
/// ★ **CP949 표본은 합성 바이트다** — 윈도우 엑셀 「CSV(쉼표)」 실물이 아직 없다(18절 0-b 「남음」).
///   CSV 출시 게이트 전에 실물 fixture로 교체한다 — **실물 교체 대기**.
@Suite("인코딩 판정 (5-3b)")
struct PackTextDecoderTests {

    private static let cp949 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.dosKorean.rawValue)))

    private func bytes(_ values: [UInt8]) -> Data { Data(values) }

    @Test("UTF-32 BOM은 UTF-16으로 오인하지 않고 지원하지 않는 인코딩으로 거부한다 (AC-17)",
          arguments: [[UInt8]([0xFF, 0xFE, 0x00, 0x00, 0x41, 0x00, 0x00, 0x00]),
                      [0x00, 0x00, 0xFE, 0xFF, 0x00, 0x00, 0x00, 0x41]])
    func utf32BOMRejected(data: [UInt8]) {
        #expect(throws: PackImportFailure.unsupportedEncoding) { try PackTextDecoder.decode(bytes(data)) }
    }

    @Test("UTF-8 BOM — 확인 화면 없이 UTF-8, BOM은 본문에서 빠진다")
    func utf8WithBOM() throws {
        let decoded = try PackTextDecoder.decode(bytes([0xEF, 0xBB, 0xBF]) + Data("번호,본문".utf8))
        #expect(decoded == DecodedPackText(text: "번호,본문", encoding: .utf8, hadBOM: true, needsConfirmation: false))
    }

    /// `B0 A1`은 CP949의 「가」 — 그래도 BOM이 UTF-8이라 선언했으니 손상으로 본다
    @Test("UTF-8 BOM인데 본문이 UTF-8이 아니면 CP949로 폴백하지 않고 전체 거부 (AC-17)")
    func utf8BOMWithInvalidBody() {
        #expect(throws: PackImportFailure.invalidUTF8AfterBOM) {
            try PackTextDecoder.decode(bytes([0xEF, 0xBB, 0xBF, 0xB0, 0xA1]))
        }
    }

    @Test("UTF-16 BOM — 짝수 바이트·서로게이트가 맞으면 받는다")
    func utf16Valid() throws {
        let little = try PackTextDecoder.decode(bytes([0xFF, 0xFE, 0x00, 0xAC, 0x2C, 0x00, 0x3D, 0xD8, 0x00, 0xDE]))
        #expect(little.text == "가,😀")
        #expect(little.encoding == .utf16LittleEndian && little.hadBOM && !little.needsConfirmation)
        let big = try PackTextDecoder.decode(bytes([0xFE, 0xFF, 0xAC, 0x00, 0x00, 0x2C]))
        #expect(big.text == "가,")
        #expect(big.encoding == .utf16BigEndian)
    }

    @Test("UTF-16 BOM인데 홀수 바이트·홀로 선 서로게이트면 거부 (AC-17)", arguments: [
        [UInt8]([0xFF, 0xFE, 0x41, 0x00, 0x42]),          // 홀수
        [0xFF, 0xFE, 0x3D, 0xD8, 0x41, 0x00],              // 높은 서로게이트 뒤 일반 글자
        [0xFF, 0xFE, 0x00, 0xDE]                           // 낮은 서로게이트 단독
    ])
    func utf16Invalid(data: [UInt8]) {
        #expect(throws: PackImportFailure.invalidUTF16) { try PackTextDecoder.decode(bytes(data)) }
    }

    @Test("BOM 없는 ASCII — 해석 차이가 없어 확인 화면 생략")
    func asciiNoConfirmation() throws {
        let decoded = try PackTextDecoder.decode(Data("trigger,body\r\na,b".utf8))
        #expect(decoded.encoding == .utf8 && !decoded.hadBOM && !decoded.needsConfirmation)
    }

    /// 구글 시트 CSV가 이 경우다(P-9 실측 — BOM 없는 UTF-8)
    @Test("BOM 없는 비ASCII UTF-8 — 엄격 UTF-8로 받고 확인 화면을 항상 띄운다 (R18)")
    func bomlessUTF8NeedsConfirmation() throws {
        let decoded = try PackTextDecoder.decode(Data("#이름,예시\r\n단축어,본문".utf8))
        #expect(decoded.encoding == .utf8 && !decoded.hadBOM && decoded.needsConfirmation)
    }

    @Test("BOM 없는 CP949(합성 — 실물 교체 대기) — 엄격 UTF-8이 실패하면 엄격 CP949, 확인 화면 (R4·R18)")
    func bomlessCP949() throws {
        let text = "#이름,예시 팩\r\n번호,제목,본문\r\n1,가나,뷁쀍 똠방각하\r\n"
        let data = try #require(text.data(using: Self.cp949))
        let decoded = try PackTextDecoder.decode(data)
        #expect(decoded.encoding == .cp949 && decoded.needsConfirmation && !decoded.hadBOM)
        #expect(decoded.text == text)
    }

    /// `C3 A9` — UTF-8로 `é`, CP949로 `챕`. 둘 다 유효라 자동 판정은 추정일 뿐이다(5-3b #5)
    @Test("같은 원본 바이트를 수동 선택마다 처음부터 다시 디코드한다 — é / 챕 (AC-18)")
    func manualChoiceRedecodesSameBytes() throws {
        let data = bytes([0xC3, 0xA9])
        let automatic = try PackTextDecoder.decode(data)
        #expect(automatic.text == "é" && automatic.encoding == .utf8 && automatic.needsConfirmation)
        let korean = try PackTextDecoder.decode(data, choice: .cp949)
        #expect(korean.text == "챕" && korean.encoding == .cp949 && korean.needsConfirmation)
        let back = try PackTextDecoder.decode(data, choice: .utf8)
        #expect(back == automatic)
    }

    @Test("수동 선택이 BOM과 어긋나면 거부 (R4)")
    func manualChoiceMustMatchBOM() {
        #expect(throws: PackImportFailure.encodingDoesNotMatchBOM) {
            try PackTextDecoder.decode(bytes([0xEF, 0xBB, 0xBF, 0x41]), choice: .cp949)
        }
        #expect(throws: PackImportFailure.encodingDoesNotMatchBOM) {
            try PackTextDecoder.decode(bytes([0xFF, 0xFE, 0x41, 0x00]), choice: .utf8)
        }
    }

    @Test("수동 선택한 인코딩으로 엄격 디코드가 실패하면 거부 — replacement character로 복구하지 않는다")
    func manualChoiceStrict() throws {
        let korean = try #require("가나".data(using: Self.cp949))
        #expect(throws: PackImportFailure.undecodable(.utf8)) { try PackTextDecoder.decode(korean, choice: .utf8) }
        #expect(throws: PackImportFailure.undecodable(.cp949)) {
            try PackTextDecoder.decode(Data("😀".utf8), choice: .cp949)
        }
    }

    @Test("BOM 없이 엄격 UTF-8·엄격 CP949 둘 다 실패하면 지원하지 않는 인코딩", arguments: [
        [UInt8]([0x41, 0x80, 0x42]),        // 둘 다에서 잘못된 바이트
        [0x61, 0x00, 0x62, 0x00]             // BOM 없는 UTF-16 — 억지로 받지 않는다(NUL)
    ])
    func bomlessUndecodable(data: [UInt8]) {
        #expect(throws: PackImportFailure.unsupportedEncoding) { try PackTextDecoder.decode(bytes(data)) }
    }

    @Test("파일 바이트 상한을 넘으면 디코드 전에 거부한다(cap+1)")
    func fileTooLarge() {
        #expect(throws: PackImportFailure.fileTooLarge) {
            try PackTextDecoder.decode(Data(repeating: 0x61, count: 3_000_001))
        }
        #expect((try? PackTextDecoder.decode(Data(repeating: 0x61, count: 3_000_000))) != nil)
    }
}
