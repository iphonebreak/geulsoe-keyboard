import Testing
@testable import KeyboardCore

/// U7 R49(2026-10-15, 사장님) — 후보 패널은 **무장(450ms) 순간 연다**, 연 뒤 손을 떼면 아무 일 없음.
/// 판정은 `SnippetCandidateGate`에 있다 — KeyboardUI `ChipPressState`는 단계를 쥐고 이 식만 부른다(VC·칩 뷰는 배선만).
/// 근거: PDR `external-snippet-packs.md` R49 · 10-6 ④⑤ · R33~R35
@Suite("U7 R49 — 무장 순간 열기 · 연 뒤 떼기 무동작")
struct SnippetCandidateOpenOnArmTests {

    @Test("열기 시점 — 누르고 있는(pressed) 동안 450ms에 무장이 허락되면 그 순간 연다", arguments: [
        // (단계, 조립 지점 허락, 열기, 허락을 물었나)
        (SnippetChipPressPhase.pressed, true, true, true),
        (.pressed, false, false, true),     // 무장 불가(후보 1개·퇴장 중·꼬리 어긋남) — 점선·피드백·패널 없음(R33)
        (.armed, true, false, false),       // 이미 무장(= 이미 열었다) — 두 번 열지 않는다
        (.cancelled, true, false, false),   // 칩 밖으로 끌려 나가 취소됨 — 늦은 타이머는 묻지도 열지도 않는다
        (.idle, true, false, false)         // 손을 뗀 뒤 늦게 온 타이머
    ] as [(SnippetChipPressPhase, Bool, Bool, Bool)])
    func opensAtArm(row: (phase: SnippetChipPressPhase, allowed: Bool, opens: Bool, asked: Bool)) {
        var asked = false
        let opens = SnippetCandidateGate.armsAndOpens(phase: row.phase, canArm: { asked = true; return row.allowed })
        #expect(opens == row.opens)
        #expect(asked == row.asked)
    }

    @Test("손 뗌 — 누름(pressed)인 채 칩 안이면 짧은 탭, 무장(=패널을 이미 연) 뒤에는 아무 일 없음", arguments: [
        (SnippetChipPressPhase.pressed, true, SnippetChipRelease.tap),     // 450ms 전 떼기 · 무장 불가 450ms+ 떼기(R33)
        (.pressed, false, .none),        // 칩 밖에서 뗌
        (.armed, true, .none),           // ★ R49 — 삽입하지 않는다(짧은 탭으로 새지 않게), 패널도 닫지 않는다
        (.armed, false, .none),
        (.cancelled, true, .none),       // R34 — 되돌아와 떼도 되살리지 않는다
        (.idle, true, .none)
    ] as [(SnippetChipPressPhase, Bool, SnippetChipRelease)])
    func release(row: (phase: SnippetChipPressPhase, inside: Bool, expected: SnippetChipRelease)) {
        #expect(SnippetCandidateGate.release(phase: row.phase, inside: row.inside) == row.expected)
    }

    @Test("칩 밖 10pt 끌림 — 누름·무장을 취소한다(이미 연 패널은 닫지 않는다 — 판정에 닫기가 없다)", arguments: [
        (SnippetChipPressPhase.pressed, false, true),
        (.armed, false, true),
        (.pressed, true, false),
        (.armed, true, false),
        (.cancelled, false, false),     // 이미 취소 — 다시 알리지 않는다
        (.idle, false, false)
    ] as [(SnippetChipPressPhase, Bool, Bool)])
    func cancel(row: (phase: SnippetChipPressPhase, inside: Bool, cancels: Bool)) {
        #expect(SnippetCandidateGate.cancels(phase: row.phase, inside: row.inside) == row.cancels)
    }

    /// 퇴장 트랜지션(0.28초) 중 칩도 히트 테스트를 받아, 450ms 뒤엔 칩이 이미 사라졌을 수 있다(10-6 ⑤).
    /// 그때 허락은 「누른 칩 구간 ∧ 지금 칩 개수」(`canArm(pressed:current:tail:)`)가 거절한다 → 열지 않고, 떼면 짧은 탭(R33) —
    /// 짧은 탭의 최종 방어는 조립 지점의 칩 동일성·꼬리 정합 그대로다
    @Test("퇴장 중 칩 — 450ms에 칩이 사라졌으면 열지 않고 떼면 짧은 탭 경로")
    func exitingChip() {
        let pressed = SnippetSuggestion(trigger: "새해인사", title: "t", body: "b", alternativeCount: 2)
        let tail = "팀장님 새해인사 "   // 사용자가 이어 쳐서 칩이 퇴장 중
        let opens = SnippetCandidateGate.armsAndOpens(phase: .pressed, canArm: {
            SnippetCandidateGate.canArm(pressed: pressed, current: nil, tail: tail)
        })
        #expect(!opens)
        #expect(SnippetCandidateGate.release(phase: .pressed, inside: true) == .tap)
    }

    /// R49 검증 2-2(권고 → 사장님 결정): 시스템이 칩 누름을 **취소**하면(제어 센터·알림 당기기·전화 배너 — `touchesCancelled`)
    /// `onEnded`가 오지 않는다. 그때 남은 누름은 **아무 동작 없이 버린다** — 450ms 전이면 유령 패널을 막고, 무장 뒤면 다음 탭이 삼켜지지 않게.
    /// 정상 손 뗌(`release`가 이미 idle로 돌림) 뒤에 또 불려도 아무것도 하지 않는다(이중 정리 무해)
    @Test("터치를 잃음 — 남은 누름은 버리고(idle 아닌 단계만), idle이면 아무것도 안 한다", arguments: [
        (SnippetChipPressPhase.pressed, true),
        (.armed, true),
        (.cancelled, true),
        (.idle, false)
    ] as [(SnippetChipPressPhase, Bool)])
    func touchLost(row: (phase: SnippetChipPressPhase, discards: Bool)) {
        #expect(SnippetCandidateGate.discardsOnTouchLost(phase: row.phase) == row.discards)
    }
}

