import Foundation
import Testing
import TadakDomain
@testable import TadakData

/// 소비한 클립보드의 기록(번호 + 지문)과 지문 열쇠 저장소 — **호스트(macOS)에서의 왕복**만 잰다.
///
/// 새 인스턴스로 읽는 것이 「키보드 프로세스가 새로 떴을 때」의 흉내다. 담는 것은 정수와 바이트뿐이다(클립보드 원문 없음).
@Suite("클립보드 소비 기록 — 전용 컨테이너 저장소", .serialized)
struct PasteboardConsumptionStoreTests {

    private let fingerprint = Data(repeating: 0xA1, count: 16)

    private func withSuite(_ body: (String) throws -> Void) rethrows {
        let suite = "tadak.tests.pasteboardConsumption.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        try body(suite)
    }

    @Test("★ 번호와 지문을 새 인스턴스가 읽는다 — 프로세스가 다시 떠도 ✕로 내린 칩이 되살아나지 않는다")
    func roundTripAcrossInstances() {
        withSuite { suite in
            let consumption = PasteboardConsumption(changeCount: 17193, fingerprint: fingerprint)
            KeyboardOwnPasteboardConsumptionStore(suiteName: suite).save(consumption)
            #expect(KeyboardOwnPasteboardConsumptionStore(suiteName: suite).load() == consumption)
        }
    }

    @Test("번호만·지문만인 기록도 왕복한다(재부팅 뒤 번호를 잃은 기록)")
    func roundTripPartialRecords() {
        withSuite { suite in
            let store = KeyboardOwnPasteboardConsumptionStore(suiteName: suite)
            store.save(PasteboardConsumption(changeCount: nil, fingerprint: fingerprint))
            #expect(store.load() == PasteboardConsumption(changeCount: nil, fingerprint: fingerprint))
            store.save(PasteboardConsumption(changeCount: 5, fingerprint: nil))
            #expect(store.load() == PasteboardConsumption(changeCount: 5, fingerprint: nil))
        }
    }

    @Test("218c612가 남긴 기록(번호만)을 그대로 읽는다")
    func readsCountOnlyRecordFromPreviousBuild() {
        withSuite { suite in
            UserDefaults(suiteName: suite)?.set(17193, forKey: KeyboardOwnPasteboardConsumptionStore.changeCountKey)
            #expect(KeyboardOwnPasteboardConsumptionStore(suiteName: suite).load()
                    == PasteboardConsumption(changeCount: 17193, fingerprint: nil))
        }
    }

    @Test("길이가 틀린 지문은 버린다")
    func dropsMalformedFingerprint() {
        withSuite { suite in
            UserDefaults(suiteName: suite)?.set(Data([1, 2, 3]), forKey: KeyboardOwnPasteboardConsumptionStore.fingerprintStorageKey)
            #expect(KeyboardOwnPasteboardConsumptionStore(suiteName: suite).load() == nil)
        }
    }

    @Test("비어 있으면 nil")
    func emptyLoad() {
        withSuite { suite in
            #expect(KeyboardOwnPasteboardConsumptionStore(suiteName: suite).load() == nil)
        }
    }

    @Test("nil을 저장하면 기록을 지운다 — 번호·지문 키가 남지 않고 열쇠는 그대로다")
    func savingNilRemoves() {
        withSuite { suite in
            let store = KeyboardOwnPasteboardConsumptionStore(suiteName: suite)
            let key = store.fingerprintKey()
            store.save(PasteboardConsumption(changeCount: 42, fingerprint: fingerprint))
            store.save(nil)
            #expect(store.load() == nil)
            let defaults = UserDefaults(suiteName: suite)
            #expect(defaults?.object(forKey: KeyboardOwnPasteboardConsumptionStore.changeCountKey) == nil)
            #expect(defaults?.object(forKey: KeyboardOwnPasteboardConsumptionStore.fingerprintStorageKey) == nil)
            #expect(store.fingerprintKey() == key)
        }
    }

    @Test("담는 값은 정수와 바이트뿐이다 — 문자열로 쓰지 않는다")
    func storesIntegerAndBytesOnly() {
        withSuite { suite in
            let store = KeyboardOwnPasteboardConsumptionStore(suiteName: suite)
            store.save(PasteboardConsumption(changeCount: 7, fingerprint: fingerprint))
            _ = store.fingerprintKey()
            let defaults = UserDefaults(suiteName: suite)
            #expect(defaults?.object(forKey: KeyboardOwnPasteboardConsumptionStore.changeCountKey) is Int)
            #expect(defaults?.object(forKey: KeyboardOwnPasteboardConsumptionStore.fingerprintStorageKey) is Data)
            #expect(defaults?.object(forKey: KeyboardOwnPasteboardConsumptionStore.secretStorageKey) is Data)
            let ours = [KeyboardOwnPasteboardConsumptionStore.changeCountKey,
                        KeyboardOwnPasteboardConsumptionStore.fingerprintStorageKey,
                        KeyboardOwnPasteboardConsumptionStore.secretStorageKey]
            #expect(ours.allSatisfy { !(defaults?.object(forKey: $0) is String) })
        }
    }

    @Test("★ 지문 열쇠는 한 번 만들면 그대로다 — 새 인스턴스도 같은 열쇠, 32바이트")
    func fingerprintKeyIsStable() {
        withSuite { suite in
            let first = KeyboardOwnPasteboardConsumptionStore(suiteName: suite).fingerprintKey()
            #expect(first.count == 32)
            #expect(KeyboardOwnPasteboardConsumptionStore(suiteName: suite).fingerprintKey() == first)
        }
    }

    @Test("지문 열쇠는 기기(저장소)마다 무작위다")
    func fingerprintKeyIsRandomPerStore() {
        withSuite { first in
            withSuite { second in
                #expect(KeyboardOwnPasteboardConsumptionStore(suiteName: first).fingerprintKey()
                        != KeyboardOwnPasteboardConsumptionStore(suiteName: second).fingerprintKey())
            }
        }
    }
}
