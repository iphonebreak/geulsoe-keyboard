import Foundation
import Testing
@testable import TadakDomain

// 외부 채움글 1-b — 저장 형식(7절)·snapshot manifest(8절)·키보드 재검사(9-4 ⑤)·재구성 키(9-5, AC-9)
// PDR `docs/design-reviews/external-snippet-packs.md`

@Suite("외부 팩 저장 형식 · 재구성 키 (1-b)")
struct ExternalPackStorageTests {

    private static let phrases = ExternalPack(
        name: "상용 영어", license: "자체 작성", mode: .phrases,
        entries: [SnippetEntry(triggers: ["감사인사"], title: "감사", body: "고맙습니다")])
    private static let numbered = ExternalPack(
        name: "사자성어", license: "자체 작성", mode: .numbered,
        template: PackTemplate(patterns: [TemplatePattern(prefix: "사자성어", suffix: "번")], titleFormat: "사자성어 {n}번",
                               items: [PackTemplateItem(n: 12, title: "", body: "온고지신")]))

    @Test("순서 칸 — 「내 채움글」과 팩 id를 글자 하나로 저장하고 되읽는다(U1)")
    func slotCodable() throws {
        let order: [SnippetSourceSlot] = [.pack("b"), .userSnippets, .pack("a:1")]
        let data = try JSONEncoder().encode(order)
        #expect(String(decoding: data, as: UTF8.self) == #"["pack:b","user","pack:a:1"]"#)
        #expect(try JSONDecoder().decode([SnippetSourceSlot].self, from: data) == order)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([SnippetSourceSlot].self, from: Data(#"["mine"]"#.utf8)) }
    }

    @Test("변환본 — schema·packID·source·stats를 감싸 왕복한다, stats는 저장 시점 값")
    func storedPackRoundTrip() throws {
        let stored = StoredExternalPack(packID: "p1", source: .csv, pack: Self.numbered)
        #expect(stored.schema == StoredExternalPack.schemaVersion)
        #expect(stored.stats == PackStats.of(pack: Self.numbered))
        let data = try JSONEncoder().encode(stored)
        #expect(try JSONDecoder().decode(StoredExternalPack.self, from: data) == stored)
    }

    @Test("manifest — generation·사용자 문구 revision·순서·팩 바이트를 담는다")
    func manifestRoundTrip() throws {
        let manifest = PackSnapshotManifest(
            generation: 7, userSnippetsRevision: 3, order: [.userSnippets, .pack("p1")],
            packs: [.init(id: "p1", file: "p1.json", bytes: 123, stats: PackStats.of(pack: Self.phrases))])
        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(PackSnapshotManifest.self, from: data)
        #expect(decoded == manifest)
        #expect(decoded.schema == PackSnapshotManifest.schemaVersion)
    }

    // MARK: 9-4 ⑤ — 키보드는 앱 검증을 믿지 않고 필드 상한을 다시 본다

    @Test("정상 팩은 통과 — 문구형·번호형")
    func validPacks() {
        #expect(Self.phrases.isWithinStoredLimits)
        #expect(Self.numbered.isWithinStoredLimits)
    }

    @Test("★ 필드 상한·모드 모양을 어긴 팩은 거절", arguments: 0..<9)
    func invalidPacks(_ index: Int) {
        var pack: ExternalPack
        switch index {
        case 0: pack = Self.phrases; pack.name = String(repeating: "가", count: 41)
        case 1: pack = Self.phrases; pack.license = String(repeating: "가", count: 121)
        case 2: pack = Self.phrases; pack.entries[0].body = String(repeating: "가", count: 3_001)
        case 3: pack = Self.phrases; pack.entries[0].triggers = Array(repeating: "단축어", count: 11)
        case 4: pack = Self.phrases; pack.entries[0].triggers = [String(repeating: "가", count: 41)]
        case 5: pack = Self.phrases; pack.template = Self.numbered.template              // 문구형인데 틀
        case 6: pack = Self.numbered; pack.template?.items[0].n = 10_000               // 번호 범위
        case 7: pack = Self.numbered
            pack.template?.patterns = Array(repeating: TemplatePattern(prefix: "사자성어", suffix: "번"), count: 9)
        default: pack = Self.numbered; pack.template?.patterns = [TemplatePattern(prefix: String(repeating: "가", count: 39), suffix: "번번")]
        }
        #expect(!pack.isWithinStoredLimits)
    }

    // MARK: 9-4 ④⑤ — 키보드가 받는 변환본(로더와 앱 검사가 함께 부르는 판정 하나, 1-c 검증 F-4)

    @Test("★ 받는 변환본 — 디코드 → schema → 팩 id → 필드 상한 순서로 본다(schema가 먼저라 낯선 버전은 다른 사유보다 앞선다)",
          arguments: 0..<6)
    func loadableStoredPack(_ index: Int) throws {
        let good = StoredExternalPack(packID: "p1", source: .csv, pack: Self.phrases)
        var stored = good
        var data: Data?
        let expected: StoredExternalPack.LoadFailure?
        switch index {
        case 0: expected = nil
        case 1: data = Data("{ 깨짐".utf8); expected = .undecodable
        case 2: stored.schema = 2; expected = .unknownSchema
        case 3: stored.packID = "p2"; expected = .packIDMismatch
        case 4: stored.pack.name = String(repeating: "가", count: 41); expected = .outOfLimits
        default: stored.schema = 2; stored.packID = "p2"; expected = .unknownSchema
        }
        switch StoredExternalPack.loadable(from: try data ?? JSONEncoder().encode(stored), packID: "p1") {
        case .success(let loaded):
            #expect(expected == nil)
            #expect(loaded == good)
        case .failure(let failure):
            #expect(failure == expected)
        }
    }

    // MARK: AC-9 — 재구성 키

    @Test("★ 테마·진동·슬라이더 같은 무관한 설정은 재구성 키를 바꾸지 않는다 (AC-9)")
    func unrelatedSettingsKeepKey() {
        let base = KeyboardSettings()
        var other = base
        other.selectedThemeID = "다른 테마"
        other.hapticIntensity = 0.1
        other.keySoundVolume = 0.2
        other.showsKeyPreview.toggle()
        other.clipboardHistoryEnabled.toggle()
        #expect(SnippetRebuildKey(settings: base, userSnippetsGeneration: 1, packsGeneration: 1)
                == SnippetRebuildKey(settings: other, userSnippetsGeneration: 1, packsGeneration: 1))
    }

    @Test("재구성 키를 바꾸는 것 — 사용자 문구·팩 generation, 끈 팩 목록, 성경 머리말, 날짜 형식, 채움글 스위치", arguments: 0..<6)
    func relevantChangesKey(_ index: Int) {
        let base = KeyboardSettings()
        var settings = base
        var user = 1, packs = 1
        switch index {
        case 0: user = 2
        case 1: packs = 2
        case 2: settings.disabledSnippetPacks.append(SnippetPack.greetings)
        case 3: settings.bibleSnippetPrefixEnabled.toggle()
        case 4: settings.dateSnippetStyle = settings.dateSnippetStyle == .formal ? .common : .formal
        default: settings.snippetsEnabled.toggle()
        }
        #expect(SnippetRebuildKey(settings: base, userSnippetsGeneration: 1, packsGeneration: 1)
                != SnippetRebuildKey(settings: settings, userSnippetsGeneration: user, packsGeneration: packs))
    }

    @Test("끈 팩 목록은 순서가 달라도 같은 키")
    func disabledOrderIgnored() {
        var a = KeyboardSettings(), b = KeyboardSettings()
        a.disabledSnippetPacks = [SnippetPack.anthem, SnippetPack.date]
        b.disabledSnippetPacks = [SnippetPack.date, SnippetPack.anthem]
        #expect(SnippetRebuildKey(settings: a, userSnippetsGeneration: 0, packsGeneration: 0)
                == SnippetRebuildKey(settings: b, userSnippetsGeneration: 0, packsGeneration: 0))
    }
}
