/// 외부 채움글 변경 알림의 **문구 표 — 한 곳**(1-c 계획서 `external-snippet-packs-1c-plan.md` 4-2절 A~G를 글자 그대로).
/// 화면은 이 표를 그대로 보인다. 패키지에 두는 이유는 문구 검사를 `swift test`로 돌리기 위해서다(5절 1단계 ④ —
/// U6 교회·성경 소재 0 · 금칙어 · 한도 숫자 0, `PackNoticeCopyLintTests`).
///
/// 규칙: 해요체 · 용어는 「단축어」「채움글」 · **한도 숫자를 쓰지 않는다**(8절 #3 — 후보값을 사용자 약속으로 굳히지 않는다) ·
/// 문구마다 **무엇을 하면 풀리는지**를 말한다(「잠시 뒤 다시」는 쓰기 실패에만 맞는 말이라 쓰지 않는다) ·
/// 「○○」에는 사용자가 정한 팩 이름(40자 이하)이 들어간다 — **표시만** 하고 로그·분석 이벤트에 싣지 않는다(보안 규칙).
public enum PackNoticeCopy {

    /// 거부를 다시 판정했을 때 문구 앞 한 줄(AC-3 `rechecked`)
    public static let recheckedLine = "그 사이 채움글이 바뀌어서 다시 확인했어요."
    /// 이름을 모르는 팩(표시 칸도 변환본도 없는 옛 목록·그 사이 지워진 팩)
    public static let unnamedPack = "이름 없는 팩"

    /// G3 — 순서 변경 화면 아래 줄(완료는 막지 않는다). 언제 띄우는지는 3단계(`PackImpact`)가 정한다
    public static func reorderWarning(names: [String]) -> String {
        "이렇게 바꾸면 \(subject(names.first ?? unnamedPack, count: max(names.count, 1))) 한도 밖으로 밀려서 쉬어요."
    }

    static func title(_ reason: PackChangeNotice.Reason) -> String {
        switch reason {
        case .userSaveTooMany, .userSaveTooLong, .userSaveWhileOverLimit, .writeFailed, .internalError: "저장하지 못했어요"
        case .builtInOverLimit, .builtInDisplacesPacks, .enableDisplacesPacks, .enableExceedsLimit, .packUnavailable: "켤 수 없어요"
        case .replaceExceedsLimit: "바꿀 수 없어요"
        case .importExceedsLimit, .importWhileUserOverLimit: "가져올 수 없어요"
        case .importTooManyPacks: "더 가져올 수 없어요"
        case .libraryUnreadable: "채움글을 바꿀 수 없어요"
        case .changedMeanwhile: "목록이 바뀌었어요"
        case .packRested, .packsRested: "저장했어요"
        }
    }

    /// - Parameters:
    ///   - firstName: 이름이 들어가는 사유(B2·C1·G1·G2)의 첫 팩 이름 — 그 밖에는 쓰지 않는다
    ///   - count: 그 팩 수 — 둘 이상이면 「「A」 외 n개」
    static func message(_ reason: PackChangeNotice.Reason, firstName: String, count: Int) -> String {
        switch reason {
        case .userSaveTooMany:          // A1
            "채움글이 너무 많아요. 안 쓰는 채움글을 지우거나 내장 팩을 끈 뒤 다시 해 주세요."
        case .userSaveTooLong:          // A2
            "채움글이 너무 길어요. 문구를 줄이거나 안 쓰는 채움글을 지운 뒤 다시 해 주세요."
        case .userSaveWhileOverLimit:   // A3
            "지금은 채움글이 한도를 넘은 상태라 문구를 늘릴 수 없어요. 줄이는 수정이나 지우기만 돼요."
        case .builtInOverLimit:         // B1
            "켜면 채움글이 한도를 넘어요. 안 쓰는 채움글을 지우거나 다른 내장 팩을 끈 뒤 켜 주세요."
        case .builtInDisplacesPacks:    // B2
            "켜면 \(subject(firstName, count: count)) 한도 밖으로 밀려요. 외부 채움글 팩을 먼저 끄거나 지운 뒤 켜 주세요."
        case .enableDisplacesPacks:     // C1
            "켜면 이 팩보다 아래에 있는 \(subject(firstName, count: count)) 한도 밖으로 밀려요. 먼저 다른 팩을 끄거나 순서를 바꿔 주세요."
        case .enableExceedsLimit:       // C2
            "켜면 한도를 넘어요. 다른 팩을 먼저 꺼 주세요."
        case .replaceExceedsLimit:      // C3
            "새 파일로 바꾸면 한도를 넘어요. 다른 팩을 먼저 끄거나 지운 뒤 다시 가져와 주세요."
        case .importExceedsLimit:       // D1
            "켜진 채움글을 모두 합치면 한도를 넘어요. 다른 외부 팩을 끄거나 지운 뒤 다시 가져와 주세요."
        case .importWhileUserOverLimit: // D2
            "내 채움글이 한도를 넘어서 외부 팩을 쓸 수 없어요. 먼저 내 채움글을 정리해 주세요. 꺼 둔 채로는 가져올 수 있어요."
        case .importTooManyPacks:       // D3
            "외부 채움글 팩이 너무 많아요. 안 쓰는 팩을 지운 뒤 다시 가져와 주세요."
        case .libraryUnreadable:        // E1
            "외부 채움글 목록을 읽을 수 없어서 지금은 채움글을 저장하거나 지울 수 없어요. 가져온 팩 파일은 지우지 않았어요. "
                + "키보드에서는 지금 쓰던 채움글이 그대로 떠요."
        case .packUnavailable:          // E2
            "이 팩의 파일을 읽을 수 없어요. 같은 이름으로 파일을 다시 가져와 바꾸거나 팩을 지워 주세요."
        case .writeFailed:              // F1
            "기기에 쓰지 못했어요. 저장 공간을 확인한 뒤 다시 해 주세요. 원래 있던 채움글은 그대로예요."
        case .changedMeanwhile:         // F2
            "그 사이 채움글이 바뀌었어요. 화면을 다시 열어 확인해 주세요."
        case .internalError:            // F3 — 내용·이름을 담지 않는다
            "문제가 생겨서 저장하지 못했어요. 앱을 다시 열어 주세요."
        case .packRested:               // G1 (AC-4)
            "대신 \(subject(firstName, count: 1)) 한도를 넘어 쉬고 있어요. 지운 것은 없어요. 채움글을 줄이면 다시 떠요."
        case .packsRested:              // G2
            "대신 「\(firstName)」 외 \(count - 1)개 팩이 한도를 넘어 쉬고 있어요. 지운 것은 없어요. 팩 목록에서 확인해 주세요."
        }
    }

    static func label(_ action: PackChangeNotice.Action) -> String {
        switch action {
        case .confirm: "확인"
        case .close: "닫기"
        case .organize: "정리하기"
        case .importDisabled: "꺼 둔 채로 가져오기"
        case .reorderPacks: "팩 순서 바꾸기"
        case .recoverLibrary: "목록 복구"
        case .deletePack: "지우기"
        }
    }

    /// 주어 — 하나면 「이름」 + 받침에 맞는 이/가, 여럿이면 「「A」 외 n개가」(계획서 4-2절 「이름이 여럿이면」)
    static func subject(_ firstName: String, count: Int) -> String {
        count > 1 ? "「\(firstName)」 외 \(count - 1)개가" : "「\(firstName)」\(subjectParticle(after: firstName))"
    }

    /// 이름 뒤 주격 조사 — 마지막 글자(문장부호·이모지는 건너뛴다)가 한글이면 받침으로, 아라비아 숫자면 읽는 소리로
    /// (2·4·5·9 = 이·사·오·구 → 「가」), 그 밖(로마자 등 읽는 법을 모르는 글자)이면 「이(가)」.
    /// 계획서 표는 「○○」가로 적었지만 이름은 사용자가 정한다 — 「…팩」가처럼 틀린 조사를 보이지 않는다
    public static func subjectParticle(after name: String) -> String {
        guard let last = name.last(where: { $0.isLetter || $0.isNumber }),
              let scalar = last.unicodeScalars.first, last.unicodeScalars.count == 1 else { return "이(가)" }
        if (0xAC00...0xD7A3).contains(scalar.value) {
            return (scalar.value - 0xAC00) % 28 == 0 ? "가" : "이"
        }
        if last.isASCII, let digit = last.wholeNumberValue {
            return [2, 4, 5, 9].contains(digit) ? "가" : "이"
        }
        return "이(가)"
    }
}
