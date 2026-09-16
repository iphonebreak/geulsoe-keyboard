/// 복사된 텍스트에서 인증번호를 추출한다.
///
/// 문자 앱의 "코드 복사"는 숫자만 담지만, 사용자가 문자 전문을 복사하는 경우도 흔하다.
/// 규칙 (PDR verification-code-paste 결정 3):
/// - 전체가 4~8자리 숫자면 그것
/// - 인증 키워드가 있을 때만, 앞뒤가 숫자·하이픈이 아닌 독립 4~8자리 run의 첫 번째
///   (전화번호 `010-1234-5678`의 조각을 코드로 오인하지 않는다)
/// - 그 외 nil — 호출자는 아무것도 삽입하지 않아야 한다
public enum VerificationCodeDetector {

    /// ★ **번호를 확실히 가리키는 말**. 이쪽이 하나라도 있으면 아래 약한 목록은 보지 않는다.
    ///
    /// 우선순위를 두는 이유 (2026-09-16): `[한국전력] 본인인증 안내 / 고객번호 482913 /
    /// 인증번호 771203` 에서 예전에는 머리말의 **「본인인증」이 먼저 앵커를 열어 고객번호**를
    /// 집었다. 앵커는 "가장 앞선" 키워드에 꽂히는데, 머리말이 본문보다 앞서기 때문이다.
    /// 「인증번호」라는 **확실한 말이 문자 어딘가에 있으면 그쪽이 이긴다**로 바꾸면 해결된다.
    private static let strongKeywords = [
        "인증번호", "인증 번호", "인증코드", "인증 코드",
        "승인번호", "확인번호", "보안코드", "보안 코드",
    ]
    /// 약한 신호 — 위가 하나도 없을 때만 본다. 뜻 가리기(`isNumberSense`)가 함께 붙는다.
    private static let weakKeywords = ["인증", "승인번호", "확인번호", "코드", "code", "otp"]

    /// run 바로 뒤에 오면 **번호가 아니라 수량**이라는 신호. 좁게 유지한다.
    ///
    /// 조사·괄호(`를·을·는·이·가·로·)·]`)는 **넣지 않는다** — 진짜 코드가 거기 붙는다
    /// (`인증번호 [268755]를`). 「번·건·개·명·회」도 넣지 않는다 — `인증번호 482913번을 입력`
    /// 같은 표기에서 진짜 코드를 놓친다.
    private static let unitSuffixes: Set<Character> = ["년", "월", "일", "시", "분", "초", "원"]

    public static func extractCode(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if isCodeLike(trimmed) {
            return trimmed
        }

        // ★ 구글 표준 꼴 `G-123456` (2026-09-15 추가).
        //
        // 아래 일반 규칙은 전화번호 조각(`010-1234-5678`)을 코드로 오인하지 않으려고
        // **하이픈에 붙은 run 을 배제**한다. 그 규칙이 구글 문자의 표준 형식을 통째로 막고 있었다
        // (조사에서 미탐으로 확인 — `G-123456 is your Google verification code`).
        //
        // 배제 규칙을 느슨하게 하지 않고 **「G-」 라는 글자를 요구하는 좁은 구멍**만 낸다.
        // `G` 앞은 문자열 시작이거나 글자·숫자가 아니어야 한다 — `SG-1234` 같은 것은 구글 꼴이 아니다.
        // 넣는 값은 **숫자만**이다(입력란에 치는 것이 숫자다).
        if let googleCode = extractGoogleStyleCode(from: trimmed) {
            return googleCode
        }

        // 가장 앞선 **유효한** 키워드의 끝 위치 — 코드는 대개 키워드 뒤에 온다
        // ("15000원 결제 승인번호 123456"에서 금액을 집지 않기 위한 규칙, 리뷰 반영)
        guard let keywordEnd = keywordAnchor(in: trimmed) else { return nil }

        let characters = Array(trimmed)
        // ★ **키워드 앞뒤 각각 「첫 후보 run」 하나씩만 본다** (2026-09-16).
        //
        // 예전에는 후보가 거절되면 루프가 그냥 다음 run으로 넘어갔다. 그래서 배제 조건을
        // 더할수록 결과가 nil이 되는 게 아니라 **다음 run이 승격**됐다 — 그리고 승격된 값
        // (`20260916`·`30481`)은 원래 값(`2026`·`50000`)보다 **OTP처럼 보여서 더 위험했다.**
        // 사용자가 봐도 코드가 아닌 숫자는 안 누르지만, 그럴듯한 숫자는 누른다.
        // 그래서 **승격 자체를 설계에서 없앤다** — 첫 후보가 잡음이면 그것으로 끝이다(nil).
        var firstBefore: String?
        var seenAfter = false
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
            defer { index = end }
            let length = end - index
            let before = index > 0 ? characters[index - 1] : nil
            let after = end < characters.count ? characters[end] : nil
            guard (4...8).contains(length),
                  !isDigitOrHyphen(before), !isDigitOrHyphen(after) else { continue }
            // 여기까지 온 것이 「후보 run」이다. 잡음이면 **건너뛰지 않고 그 자리에서 끝낸다.**
            let noisy = isUnitSuffix(after) || isDateSeparated(characters, end: end)
            if index >= keywordEnd {
                if seenAfter { continue }   // 키워드 뒤 첫 후보만 본다
                seenAfter = true
                return noisy ? nil : String(characters[index..<end])
            }
            if firstBefore == nil {
                firstBefore = noisy ? "" : String(characters[index..<end])
            }
        }
        // 키워드 뒤에 후보가 없으면 앞쪽 첫 후보로 폴백한다 (`483920 is your Instagram code`).
        // 빈 문자열은 "첫 후보가 잡음이었다"는 표시다 — 다음 것으로 넘어가지 않는다.
        return (firstBefore?.isEmpty == false) ? firstBefore : nil
    }

    /// 가장 앞선 **유효한** 키워드의 끝. 없으면 nil.
    ///
    /// ## ★ 「인증」·「코드」는 번호를 안 가리킬 때가 있다 (2026-09-16)
    ///
    /// 예전에는 `range(of:)`로 **첫 출현 하나**만 봤다. 그래서 이런 문자에서 헛걸렸다
    /// (전부 실측 재현):
    ///
    /// | 문자 | 옛 결과 | 왜 |
    /// |---|---|---|
    /// | `금융인증서 유효기간이 2026년 9월 30일 만료됩니다` | `2026` | 「인증**서**」의 인증 |
    /// | `공동인증서 갱신 안내 1588 0000` | `1588` | 위와 같음 |
    /// | `[쿠팡] 첫 구매 할인코드로 3000원 즉시 할인!` | `3000` | 「할인**코드**」의 코드 |
    ///
    /// 공동·금융인증서 만료 안내는 한국에서 아주 흔한 문자다. 그리고 이 오탐의 대가는
    /// **인증 실패로 끝나지 않는다** — `PasteSuggestion.make`가 "인증번호가 뽑히면 그쪽이
    /// 이긴다"라서, 엉뚱한 숫자가 뽑히면 사용자가 **원래 복사한 것을 붙여넣을 「복사됨」 칩
    /// 자체를 잃는다.**
    ///
    /// 그래서 **뜻을 가려서** 무효한 출현은 건너뛰고 **다음 출현**을 찾는다. 키워드를 목록에서
    /// 빼 버리지 않는 이유는, 빼면 앵커가 닫히는 게 아니라 **뒤로 밀려** 진짜 코드를 지나쳐
    /// 엉뚱한 숫자에 꽂히기 때문이다(반증에서 실측으로 확인).
    private static func keywordAnchor(in text: String) -> Int? {
        let characters = Array(text)
        let lowered = characters.map { Character($0.lowercased()) }
        if let strong = earliestAnchor(in: characters, lowered: lowered, among: strongKeywords) {
            return strong
        }
        var best: Int?
        for keyword in weakKeywords {
            let needle = Array(keyword.lowercased())
            guard needle.count <= lowered.count else { continue }
            for start in 0...(lowered.count - needle.count) {
                guard Array(lowered[start..<(start + needle.count)]) == needle else { continue }
                let end = start + needle.count
                guard isNumberSense(keyword, in: characters, start: start, end: end) else { continue }
                if best == nil || end < best! { best = end }
                break   // 이 키워드는 **첫 유효 출현**만 본다
            }
        }
        return best
    }

    /// 목록 중 가장 앞선 출현의 끝. 강한 키워드는 뜻 가리기가 필요 없다 — 이미 명시적이다.
    private static func earliestAnchor(
        in characters: [Character], lowered: [Character], among list: [String]
    ) -> Int? {
        var best: Int?
        for keyword in list {
            let needle = Array(keyword.lowercased())
            guard needle.count <= lowered.count else { continue }
            for start in 0...(lowered.count - needle.count)
            where Array(lowered[start..<(start + needle.count)]) == needle {
                let end = start + needle.count
                if best == nil || end < best! { best = end }
                break
            }
        }
        return best
    }

    /// 이 출현이 **번호를 가리키는** 뜻인가.
    private static func isNumberSense(
        _ keyword: String, in characters: [Character], start: Int, end: Int
    ) -> Bool {
        switch keyword {
        case "인증":
            // 「인증서」는 증명서지 번호가 아니다 (공동·금융인증서 만료·갱신 안내).
            return end >= characters.count || characters[end] != "서"
        case "코드":
            // 「할인코드·쿠폰코드·바코드·초대코드」는 인증이 아니다.
            // 앞이 한글이면 합성어로 본다 — 단 「인증코드·보안코드·확인코드」는 통과시킨다.
            guard start > 0, characters[start - 1].isHangulSyllable else { return true }
            guard start >= 2 else { return false }
            let prefix = String(characters[(start - 2)..<start])
            return ["인증", "보안", "확인"].contains(prefix)
        default:
            return true
        }
    }

    /// run 뒤가 `.` 또는 `/` 이고 **그 다음이 숫자**면 날짜·버전 표기다 (`2026.09.30`).
    /// **"다음이 숫자일 때"로 좁히는 것이 핵심이다** — `.` 만으로 배제하면 문장 끝
    /// (`Your OTP code is 553201.`)이 통째로 미탐된다.
    private static func isDateSeparated(_ characters: [Character], end: Int) -> Bool {
        guard end < characters.count, characters[end] == "." || characters[end] == "/",
              end + 1 < characters.count,
              characters[end + 1].isASCII, characters[end + 1].isNumber else { return false }
        return true
    }

    private static func isUnitSuffix(_ character: Character?) -> Bool {
        guard let character else { return false }
        return unitSuffixes.contains(character)
    }

    /// `G-123456` 꼴에서 숫자만 뽑는다. 못 찾으면 nil.
    private static func extractGoogleStyleCode(from text: String) -> String? {
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            guard characters[index] == "G" || characters[index] == "g",
                  index + 1 < characters.count, characters[index + 1] == "-" else {
                index += 1
                continue
            }
            // 「G」 앞이 글자·숫자면 구글 꼴이 아니다 (`SG-1234`)
            if index > 0, characters[index - 1].isLetter || characters[index - 1].isNumber {
                index += 1
                continue
            }
            var end = index + 2
            while end < characters.count, characters[end].isASCII, characters[end].isNumber {
                end += 1
            }
            let length = end - (index + 2)
            // 숫자 뒤에 또 하이픈+숫자가 이어지면 전화번호류다 — 넘긴다
            let after = end < characters.count ? characters[end] : nil
            if (4...8).contains(length), after != "-" {
                return String(characters[(index + 2)..<end])
            }
            index += 1
        }
        return nil
    }

    private static func isCodeLike(_ text: String) -> Bool {
        (4...8).contains(text.count) && text.allSatisfy { $0.isASCII && $0.isNumber }
    }

    private static func isDigitOrHyphen(_ character: Character?) -> Bool {
        guard let character else { return false }
        return (character.isASCII && character.isNumber) || character == "-"
    }
}

private extension Character {
    /// 한글 음절(가~힣). 「할인코드」처럼 합성어인지 가르는 데 쓴다.
    var isHangulSyllable: Bool {
        guard let scalar = unicodeScalars.first, unicodeScalars.count == 1 else { return false }
        return (0xAC00...0xD7A3).contains(scalar.value)
    }
}
