/// 지우고 넣는 치환(채움글·U7 후보 행·성경 패널 행·이모지 칩·추천단어 탭) 전에 보는 두 조건 — codex 반론 v1.3.0(키보드)
/// K1·K4(사장님 결정 2026-10-08, 원문 `docs/release/counter-v130-codex-kb.md` #1·#4).
///
/// 판정은 여기 한 곳이다. **최종 방어**는 `InputController`의 치환 함수들이 이 식으로 거절하는 것이고, 조립 지점은 같은 식으로
/// 칩·배지를 **띄우지 않는다**(눌러도 거절되는 후보를 남기지 않는다 — 표시와 거절이 같은 식이어야 한다).
/// 입력은 정수와 참·거짓뿐이다 — 선택한 글자·넣은 본문을 들지 않는다(보안 규칙).
public enum ReplacementGate {

    /// K4 — 호스트 문서에 **선택 영역**이 있으면 치환하지 않는다. 첫 `deleteBackward`가 선택 영역을 지우는 호스트에서는
    /// 나머지 삭제 횟수가 어긋나 선택한 글과 단축어 앞 글자가 함께 사라지고 꼬리가 문서와 갈라진다.
    /// 키 입력·⌫는 막지 않는다 — 선택 영역을 바꾸는 것은 시스템 키보드와 같은 동작이고, 뒤따르는 sync가 꼬리를 다시 세운다
    public static func allowsReplacement(hasSelectedText: Bool) -> Bool {
        !hasSelectedText
    }

    /// K1 — 채움글을 넣은 뒤 **문서 쓰기 횟수가 그대로면**(다음 사용자 편집 전) 채움글 칩·삽입을 보류한다.
    ///
    /// 본문이 자기 단축어로 끝나면(「주소 → 서울 주소」) 같은 후보가 곧바로 다시 맞는다 — 퇴장 중(0.28초) 옛 칩 재탭이 VC의
    /// 동일성 검사와 꼬리 정합을 모두 통과해 `서울 서울 주소`가 됐다. 삽입 직후 맞는 구간은 **끝이 반드시 방금 넣은 글 안**에 있으므로
    /// (경계를 걸친 「가가나 → 가나」까지) 구간 길이를 따지지 않고 통째로 보류한다(코디네이터 회신 A안).
    ///
    /// 풀리는 것은 문서가 실제로 바뀔 때뿐이다 — 한 글자 치기·지우기·리턴·스페이스, 다른 칩 탭(추천단어·이모지·붙여넣기).
    /// ⇧·한영·123, 호스트 메아리 sync, 커서 이동은 풀지 않는다(이모지 D17과 같은 `documentRevision` 기준)
    public static func holdsSnippets(revisionAfterSnippetInsertion: Int?, documentRevision: Int) -> Bool {
        revisionAfterSnippetInsertion == documentRevision
    }

    /// 채움글 삽입 경로(칩·U7 후보 행·성경 배지와 패널 행 — 모두 `insertSnippet`)를 지금 써도 되나 — K1 보류가 아니고 선택 영역이 없을 때만
    public static func allowsSnippetInsertion(isHeldAfterInsertion: Bool, hasSelectedText: Bool) -> Bool {
        !isHeldAfterInsertion && allowsReplacement(hasSelectedText: hasSelectedText)
    }
}
