import Foundation
import Testing
import TadakDomain
@testable import TadakData

/// 소비한 클립보드의 `changeCount` 저장소 — **호스트(macOS)에서의 왕복**만 잰다.
///
/// 새 인스턴스로 읽는 것이 「키보드 프로세스가 새로 떴을 때」의 흉내다. 담는 것은 정수 하나뿐이다(클립보드 내용 없음).
@Suite("클립보드 소비 기록 — 전용 컨테이너 저장소", .serialized)
struct PasteboardConsumptionStoreTests {

    private func withSuite(_ body: (String) throws -> Void) rethrows {
        let suite = "tadak.tests.pasteboardConsumption.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        try body(suite)
    }

    @Test("★ 저장한 값을 새 인스턴스가 읽는다 — 프로세스가 다시 떠도 ✕로 내린 칩이 되살아나지 않는다")
    func roundTripAcrossInstances() {
        withSuite { suite in
            KeyboardOwnPasteboardConsumptionStore(suiteName: suite).save(17193)
            #expect(KeyboardOwnPasteboardConsumptionStore(suiteName: suite).load() == 17193)
        }
    }

    @Test("비어 있으면 nil")
    func emptyLoad() {
        withSuite { suite in
            #expect(KeyboardOwnPasteboardConsumptionStore(suiteName: suite).load() == nil)
        }
    }

    @Test("nil을 저장하면 지운다 — 남는 키가 없다")
    func savingNilRemoves() {
        withSuite { suite in
            let store = KeyboardOwnPasteboardConsumptionStore(suiteName: suite)
            store.save(42)
            store.save(nil)
            #expect(store.load() == nil)
            #expect(UserDefaults(suiteName: suite)?.object(forKey: KeyboardOwnPasteboardConsumptionStore.key) == nil)
        }
    }

    @Test("담는 값은 정수 하나다 — 문자열·데이터로 쓰지 않는다")
    func storesIntegerOnly() {
        withSuite { suite in
            KeyboardOwnPasteboardConsumptionStore(suiteName: suite).save(7)
            #expect(UserDefaults(suiteName: suite)?.object(forKey: KeyboardOwnPasteboardConsumptionStore.key) is Int)
        }
    }
}
