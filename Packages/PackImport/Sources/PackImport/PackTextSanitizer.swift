import Foundation

/// 문자 정리(PDR `external-snippet-packs.md` 11절, v2 10-3) — 순서가 계약이다.
///
/// 1. CRLF·CR → LF(제어 문자 제거 **전**), `U+2028`·`U+2029` → LF
/// 2. 제어 문자 제거 — `U+0000–001F`(LF·탭 제외), `U+007F–009F`
/// 3. 위험한 보이지 않는 문자 제거 — bidi 재정의·격리 `U+202A–202E`·`U+2066–2069`, 방향 표식 `U+200E/F`,
///    제로폭 공백 `U+200B`, 단어 접합 `U+2060`, 본문 중 `U+FEFF`
/// 4. **보존** — ZWJ `U+200D`(가족 이모지)·ZWNJ `U+200C`·변이 선택자
/// 5. 맨 앞·맨 뒤에 홀로 선 ZWJ 제거
///
/// `removed`는 미리보기의 「정리 N건」(조용히 바꾸지 않는다) — 줄끝 통일(CRLF→LF)은 정상 표기라 세지 않는다.
/// 정리 **뒤에** 상한·빈 값·중복을 다시 검사하는 것은 부르는 쪽(가져오기)이다.
public enum PackTextSanitizer {

    public static func sanitize(_ text: String) -> (text: String, removed: Int) {
        var scalars: [Unicode.Scalar] = []
        scalars.reserveCapacity(text.unicodeScalars.count)
        var removed = 0
        var previousWasCR = false
        for scalar in text.unicodeScalars {
            let value = scalar.value
            defer { previousWasCR = value == 0x0D }
            switch value {
            case 0x0D:
                scalars.append("\n")
            case 0x0A:
                if !previousWasCR { scalars.append("\n") }       // CRLF의 LF는 이미 넣었다
            case 0x2028, 0x2029:
                scalars.append("\n")
                removed += 1
            case 0x09:
                scalars.append(scalar)
            case 0x00...0x1F, 0x7F...0x9F,
                 0x202A...0x202E, 0x2066...0x2069, 0x200E, 0x200F, 0x200B, 0x2060, 0xFEFF:
                removed += 1
            default:
                scalars.append(scalar)
            }
        }
        // 앞 ZWJ는 세어 한 번에 뗀다 — 하나씩 `removeFirst()`하면 앞 ZWJ 수 × 길이(3MB 붙여넣기 33초, 검증 F3). 뒤는 `removeLast`가 O(1)
        let leadingZWJ = scalars.prefix { $0 == "\u{200D}" }.count
        scalars.removeFirst(leadingZWJ)
        removed += leadingZWJ
        while scalars.last == "\u{200D}" {
            scalars.removeLast()
            removed += 1
        }
        var result = ""
        result.unicodeScalars.append(contentsOf: scalars)
        return (result, removed)
    }
}
