/// 복사된 텍스트에서 인증번호를 추출한다.
///
/// 문자 앱의 "코드 복사"는 숫자만 담지만, 사용자가 문자 전문을 복사하는 경우도 흔하다.
/// 규칙 (PDR verification-code-paste 결정 3):
/// - 전체가 4~8자리 숫자면 그것
/// - 인증 키워드가 있을 때만, 앞뒤가 숫자·하이픈이 아닌 독립 4~8자리 run의 첫 번째
///   (전화번호 `010-1234-5678`의 조각을 코드로 오인하지 않는다)
/// - 그 외 nil — 호출자는 아무것도 삽입하지 않아야 한다
public enum VerificationCodeDetector {

    private static let keywords = ["인증", "승인번호", "확인번호", "코드", "code", "otp"]

    public static func extractCode(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if isCodeLike(trimmed) {
            return trimmed
        }

        // 가장 앞선 키워드의 끝 위치 — 코드는 대개 키워드 뒤에 온다
        // ("15000원 결제 승인번호 123456"에서 금액을 집지 않기 위한 규칙, 리뷰 반영)
        let keywordEnd = keywords
            .compactMap { trimmed.range(of: $0, options: .caseInsensitive) }
            .map { trimmed.distance(from: trimmed.startIndex, to: $0.upperBound) }
            .min()
        guard let keywordEnd else { return nil }

        let characters = Array(trimmed)
        var firstRun: String?
        var index = 0
        while index < characters.count {
            guard characters[index].isASCII, characters[index].isNumber else {
                index += 1
                continue
            }
            var end = index
            while end < characters.count, characters[end].isASCII, characters[end].isNumber {
                end += 1
            }
            let length = end - index
            let before = index > 0 ? characters[index - 1] : nil
            let after = end < characters.count ? characters[end] : nil
            if (4...8).contains(length),
               !isDigitOrHyphen(before), !isDigitOrHyphen(after) {
                let run = String(characters[index..<end])
                if index >= keywordEnd {
                    return run  // 키워드 이후 첫 독립 run — 최우선
                }
                if firstRun == nil { firstRun = run }
            }
            index = end
        }
        return firstRun  // 키워드 뒤에 run이 없으면 앞쪽 run으로 폴백
    }

    private static func isCodeLike(_ text: String) -> Bool {
        (4...8).contains(text.count) && text.allSatisfy { $0.isASCII && $0.isNumber }
    }

    private static func isDigitOrHyphen(_ character: Character?) -> Bool {
        guard let character else { return false }
        return (character.isASCII && character.isNumber) || character == "-"
    }
}
