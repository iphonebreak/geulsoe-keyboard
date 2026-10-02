import Foundation
import TadakDomain

/// `bible.tdb`의 본문 블롭을 **바이트 그대로** 훑어 낱말이 든 절을 찾는다.
///
/// 설계: `docs/design-reviews/v1.1.0-plan-v5.md` 3절 · 실측 `v1.1.0-round2-findings.md` A·B절.
///
/// ## ★ 왜 `String`을 안 만드나 — 이것이 성능의 전부다
///
/// 절마다 `String(data:)`를 만들어 `contains`하면 「사랑」 한 번에 **101.999ms, 240배**다(실측).
/// 바이트 대 바이트로 훑으면 **0.43ms**다. 그래서 이 파일에는 매치를 **확정한 뒤에도**
/// `String`을 만드는 자리가 거의 없다 — 편집 안내 절(아래 blocklist)을 가려낼 때뿐이고,
/// 그건 31,102절 중 67절에서만 일어난다.
///
/// ## ★ 최희소 바이트 앵커
///
/// `memchr`로 건너뛸 때 **needle의 첫 바이트**를 쓰면 4~17배 느리다 — 한글 음절의 첫 바이트
/// (0xEA~0xED)는 본문에 극도로 흔해서 건너뛰기가 거의 일어나지 않는다. 그래서 needle의 UTF-8
/// 바이트 중 **본문 전체에서 가장 드문 것**을 골라 그 바이트로 건너뛴다.
/// 빈도표는 `init`에서 **한 번만** 만든다.
struct BibleByteScanner: Sendable {

    /// 스캔을 돌릴 최소 글자 수. 「이」 한 글자가 24,640건(전체의 79.2%)이라 결과로서 의미가 없다.
    /// **정확 스캔의 것이다** — 띄어쓰기 무시 스캔의 최소 길이(4자)는 도메인 규칙이라
    /// `KeyboardCore.BibleSearchCascade`가 건다.
    static let minimumQueryLength = 2

    /// 띄어쓰기 무시 비교에서 **매치 시작점을 뒤로 물려 볼 최대 칸수.**
    ///
    /// 최희소 바이트 앵커를 버릴 수 없어서 필요한 값이다(첫 바이트 앵커는 4~17배 느리다).
    /// 앵커가 needle 안 `anchor`번째 바이트인데 본문에 공백이 끼면 실제 시작점이
    /// `position - anchor`보다 **공백 수만큼 앞**이다. 그래서 앵커 히트마다 0~4칸을 물려 가며
    /// 공백 건너뛰기 비교를 돌린다.
    ///
    /// ## ★ 4의 성격 — 「맞바꿈 지점」이 아니라 **구조가 정한 값**이다 (2026-09-21 정정)
    ///
    /// 예전 주석은 *"비용과 회수의 맞바꿈 지점(프로토타입 실측)"*이라고 적었다. **틀렸다.**
    /// 반론자1이 재 보니 이 값은 **낱말 창 상한에서 나온다**:
    ///
    /// 캐스케이드는 꼬리에서 **최대 5낱말**(`BibleSearchCascade.wordWindowLimit`)을 한 덩어리로
    /// 잡는다. 낱말 5개 사이에는 공백이 **4개**다. 그러니 건너뛸 공백의 상한도 4다 —
    /// 그보다 크면 쓸 일이 없고, **3으로 줄이면 5낱말 질의가 0% 발견**으로 떨어진다(실측).
    ///
    /// **그래서 상수를 따로 두지 않고 낱말 창 상한에서 파생시킨다** — 둘을 따로 두면
    /// 한쪽만 바꿀 때 조용히 어긋난다. `wordWindowLimit`을 6으로 올리면 이 값도 5가 돼야 한다.
    ///
    /// `KeyboardCore`를 import할 수 없으므로(의존성 방향이 반대다) 숫자를 여기 두되
    /// **관계를 주석과 테스트로 묶는다**(`BibleSpaceInsensitiveTests.maxSpacesFollowsWordWindow`).
    static let wordWindowLimit = 5
    static let maximumSkippedSpaces = wordWindowLimit - 1

    /// **협조적 취소를 몇 절마다 확인하나** (2026-09-21, 반론자2).
    ///
    /// 스캔이 `Task.detached` 안에서 도는데 절 루프에 확인점이 하나도 없었다 —
    /// 스케줄러가 취소를 보내도 31,102절을 **끝까지** 돌았고, 키보드가 내려가도 돌았다.
    ///
    /// ## ★ 256을 고른 근거 — **재 보고 골랐다**
    ///
    /// 걱정은 「절 하나당 일이 수십 ns(한 바퀴 0.5~1.7ms ÷ 31,102절 ≈ 16~55ns)인데
    /// `Task.isCancelled`를 매 절마다 부르면 그 비율이 그대로 회귀가 된다」였다.
    ///
    /// 그래서 **간격을 4배로 늘려 보고 값이 달라지는지 확인했다**(release, 각 3회의 최솟값):
    ///
    /// | 꼬리 | 확인 없음 | N=256 | N=1024 |
    /// |---|---|---|---|
    /// | 벤치 fixture | 4.81ms | 4.89 | 4.87 |
    /// | 실사용 문장 | 5.83 | 5.92 | 5.92 |
    /// | 비싼 낱말 다섯 | 11.52 | 11.63 | 11.62 |
    ///
    /// **N을 4배로 늘려도 값이 같다.** 즉 비용은 확인 *횟수*가 아니라 **루프 안 분기 하나**이고,
    /// 간격을 넓혀서 얻을 것이 없다. 전체 비용은 **+1.0~1.7%**로 회차 간 잡음 폭(±3%) 안이다.
    ///
    /// 그러니 **반응이 가장 빠른 쪽**을 고른다 — 256은 2의 거듭제곱이라 `index & 255`로 끝나고
    /// (나눗셈 없음), 확인 간격이 최악에도 256 × 55ns ≈ **14µs**다.
    ///
    /// `index == 0`에서도 확인한다 — **이미 취소된 태스크 안에서 부르면 한 절도 안 돈다.**
    /// (`BibleSearchTests.cancelledScanStopsImmediately`가 이것을 결정적으로 잰다.)
    static let cancellationCheckInterval = 256

    private let data: Data
    private let verseCount: Int
    private let indexStart: Int
    private let entrySize: Int
    private let textStart: Int

    /// 바이트값(0...255) → 본문 블롭 전체 출현 횟수. 앵커를 고르는 데만 쓴다.
    private let byteFrequency: [UInt32]

    /// 정의형 판정에 쓰는 조사 넷의 UTF-8 바이트(`은`·`는`·`이`·`가`, 각 3바이트).
    private static let particles: [[UInt8]] = ["은", "는", "이", "가"].map { Array($0.utf8) }

    init(data: Data, verseCount: Int, indexStart: Int, entrySize: Int, textStart: Int) {
        self.data = data
        self.verseCount = verseCount
        self.indexStart = indexStart
        self.entrySize = entrySize
        self.textStart = textStart

        var counts = [UInt32](repeating: 0, count: 256)
        counts.withUnsafeMutableBufferPointer { table in
            data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      textStart < raw.count else { return }
                var i = textStart
                let end = raw.count
                while i < end {
                    table[Int(base[i])] &+= 1
                    i &+= 1
                }
            }
        }
        byteFrequency = counts
    }

    /// 스캔 한 번에 절 하나에서 모으는 것 — 주소 + 랭킹 신호 둘. **같은 루프에서 공짜로 나온다.**
    private struct Hit {
        let book: Int
        let chapter: Int
        let verse: Int
        /// (가) 절이 `낱말 + 은/는/이/가`로 시작하는가 — 정의형
        let isDefinitional: Bool
        /// (다) 절 안에서 몇 번 나오는가
        let occurrences: Int
    }

    func search(_ query: String, limit: Int) -> [BibleVerseMatch] {
        guard query.count >= Self.minimumQueryLength else { return [] }
        return run(needle: Array(query.utf8), limit: limit, skippingSpaces: false)
    }

    /// **띄어쓰기를 보지 않는** 검색 — needle에서 공백을 빼고, 본문 쪽 공백은 건너뛰며 비교한다.
    ///
    /// 「오래참음」이 본문의 「오래 참음」을 찾는다. 랭킹·상한 규칙은 정확 스캔과 **완전히 같다**
    /// (같은 `run`을 탄다).
    ///
    /// **최소 길이 4자는 여기서 보지 않는다** — 「구절은 낱말 둘 이상」이라는 판단은 도메인 규칙이라
    /// 캐스케이드가 건다. 여기서는 2자 미만만 막는다(정확 스캔과 같은 하한).
    func searchIgnoringSpaces(_ query: String, limit: Int) -> [BibleVerseMatch] {
        let squeezed = query.filter { !$0.isWhitespace }
        guard squeezed.count >= Self.minimumQueryLength else { return [] }
        return run(needle: Array(squeezed.utf8), limit: limit, skippingSpaces: true)
    }

    private func run(needle: [UInt8], limit: Int, skippingSpaces: Bool) -> [BibleVerseMatch] {
        guard limit > 0, verseCount > 0, !needle.isEmpty else { return [] }

        // 최희소 바이트 앵커 — needle 안에서 본문 빈도가 가장 낮은 바이트의 자리
        var anchor = 0
        for i in needle.indices where byteFrequency[Int(needle[i])] < byteFrequency[Int(needle[anchor])] {
            anchor = i
        }

        let hits = scan(needle: needle, anchor: anchor, skippingSpaces: skippingSpaces)
        guard !hits.isEmpty else { return [] }

        // (나) 같은 장에 몇 절이나 맞았는가 — 스캔이 끝난 뒤 집계한다
        var versesInChapter: [Int: Int] = [:]
        for hit in hits {
            versesInChapter[hit.book << 16 | hit.chapter, default: 0] += 1
        }

        // ★ 상한은 **정렬 뒤**에 건다. 스캔 도중 100건에서 끊으면 성경순 338번째인
        //   고린도전서 13:4가 후보에 아예 못 들어온다 (findings A-4).
        let ranked = hits.sorted { lhs, rhs in
            if lhs.isDefinitional != rhs.isDefinitional { return lhs.isDefinitional }
            let lc = versesInChapter[lhs.book << 16 | lhs.chapter] ?? 0
            let rc = versesInChapter[rhs.book << 16 | rhs.chapter] ?? 0
            if lc != rc { return lc > rc }
            if lhs.occurrences != rhs.occurrences { return lhs.occurrences > rhs.occurrences }
            if lhs.book != rhs.book { return lhs.book < rhs.book }
            if lhs.chapter != rhs.chapter { return lhs.chapter < rhs.chapter }
            return lhs.verse < rhs.verse
        }

        return ranked.prefix(limit).map {
            BibleVerseMatch(book: $0.book, chapter: $0.chapter, verse: $0.verse)
        }
    }

    /// 맞은 절 **전부**를 모은다 — 자르지 않는다(자르는 것은 정렬 뒤 호출자 몫).
    private func scan(needle: [UInt8], anchor: Int, skippingSpaces: Bool) -> [Hit] {
        data.withUnsafeBytes { raw -> [Hit] in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return [] }
            let total = raw.count

            return needle.withUnsafeBufferPointer { needleBuffer -> [Hit] in
                guard let needlePointer = needleBuffer.baseAddress else { return [] }
                let needleLength = needleBuffer.count
                let anchorByte = Int32(needleBuffer[anchor])

                var hits: [Hit] = []
                for index in 0..<verseCount {
                    // 협조적 취소 — 새 꼬리가 들어왔거나 키보드가 내려갔으면 여기서 그만둔다.
                    // 취소된 스캔의 결과는 호출자가 어차피 버리므로 빈 배열로 돌아가면 된다.
                    if index & (Self.cancellationCheckInterval - 1) == 0, Task.isCancelled {
                        return []
                    }
                    let entry = indexStart + index * entrySize
                    guard entry + entrySize <= total else { break }

                    let length = Int(Self.loadUInt16(base, entry + 6))
                    let offset = textStart + Int(Self.loadUInt32(base, entry + 8))
                    guard length >= needleLength, offset + length <= total else { continue }

                    let verse = base + offset
                    let occurrences = Self.countMatches(
                        in: verse, length: length,
                        needle: needlePointer, needleLength: needleLength, anchor: anchor,
                        anchorByte: anchorByte, skippingSpaces: skippingSpaces
                    )
                    guard occurrences > 0 else { continue }
                    // 본문이 아니라 편집 안내가 든 34절은 검색 결과에서 뺀다
                    guard !Self.isEditorialNotice(verse, length) else { continue }

                    // (가) 정의형 — 절 **머리**에서 맞고 바로 뒤에 조사가 오는가.
                    //     느슨 스캔에서는 맞은 구간이 공백만큼 길어지므로 실제 소비 길이로 뒤를 본다.
                    var isDefinitional = false
                    let head = Self.matchLength(
                        in: verse, from: 0, length: length,
                        needle: needlePointer, needleLength: needleLength,
                        skippingSpaces: skippingSpaces
                    )
                    if head > 0, length >= head + 3 {
                        let tail = verse + head
                        isDefinitional = Self.particles.contains { particle in
                            particle.withUnsafeBufferPointer { memcmp(tail, $0.baseAddress!, 3) == 0 }
                        }
                    }

                    hits.append(
                        Hit(
                            book: Int(Self.loadUInt16(base, entry)),
                            chapter: Int(Self.loadUInt16(base, entry + 2)),
                            verse: Int(Self.loadUInt16(base, entry + 4)),
                            isDefinitional: isDefinitional,
                            occurrences: occurrences
                        )
                    )
                }
                return hits
            }
        }
    }

    /// 절 하나에서 needle이 몇 번 나오는지 — **앵커 바이트로 건너뛰며** 센다.
    ///
    /// ## 띄어쓰기 무시일 때 시작점을 물려 보는 이유
    ///
    /// 앵커가 needle의 `anchor`번째 바이트라 정확 비교에서는 시작점이 `position - anchor`로 확정된다.
    /// 그런데 본문에 공백이 끼면 실제 시작점이 **그보다 공백 수만큼 앞**이다.
    /// 그래서 앵커 히트마다 `0...maximumSkippedSpaces`칸을 물려 가며 비교한다
    /// (앵커 자체는 그대로 쓴다 — 버리면 4~17배 느려진다).
    private static func countMatches(
        in verse: UnsafePointer<UInt8>,
        length: Int,
        needle: UnsafePointer<UInt8>,
        needleLength: Int,
        anchor: Int,
        anchorByte: Int32,
        skippingSpaces: Bool
    ) -> Int {
        // 매치가 s에서 시작하면 앵커 바이트는 s+anchor에 있다. 공백이 끼면 그만큼 뒤로 밀리므로
        // 느슨 비교에서는 앵커를 찾아볼 구간이 끝까지 늘어난다.
        let highest = skippingSpaces
            ? length - 1
            : length - needleLength + anchor
        guard highest >= anchor else { return 0 }

        var cursor = anchor
        var count = 0
        var consumedUntil = 0   // 이미 센 매치의 끝 — 겹쳐 세지 않는다
        while cursor <= highest {
            guard let found = memchr(verse + cursor, anchorByte, highest - cursor + 1) else { break }
            let position = UnsafeRawPointer(found) - UnsafeRawPointer(verse)

            if skippingSpaces {
                for skipped in 0...maximumSkippedSpaces {
                    let start = position - anchor - skipped
                    guard start >= 0 else { break }
                    guard start >= consumedUntil else { continue }
                    let matched = matchLength(
                        in: verse, from: start, length: length,
                        needle: needle, needleLength: needleLength, skippingSpaces: true
                    )
                    if matched > 0 {
                        count += 1
                        consumedUntil = start + matched
                        break
                    }
                }
            } else {
                let start = position - anchor
                if start >= 0, memcmp(verse + start, needle, needleLength) == 0 {
                    count += 1
                }
            }
            cursor = position + 1
        }
        return count
    }

    /// `start`에서 시작해 needle이 **몇 바이트를 소비하며** 맞는가. 안 맞으면 0.
    ///
    /// 느슨 비교는 **본문 쪽 공백만 건너뛴다** — needle은 이미 공백이 빠진 상태다.
    /// 그래서 돌려주는 길이는 **공백을 포함한 본문 구간의 길이**다
    /// (「오래 참음」을 「오래참음」으로 찾으면 13바이트가 아니라 공백 1바이트를 더한 값).
    /// 정의형 판정이 그 뒤에 오는 조사를 보려면 이 값이 필요하다.
    private static func matchLength(
        in verse: UnsafePointer<UInt8>,
        from start: Int,
        length: Int,
        needle: UnsafePointer<UInt8>,
        needleLength: Int,
        skippingSpaces: Bool
    ) -> Int {
        guard start >= 0, start < length else { return 0 }
        if !skippingSpaces {
            guard start + needleLength <= length else { return 0 }
            return memcmp(verse + start, needle, needleLength) == 0 ? needleLength : 0
        }
        // 첫 바이트가 공백이면 여기서 시작하는 매치가 아니다 — 시작점을 흐리지 않는다
        guard verse[start] != Self.space else { return 0 }

        var haystack = start
        var index = 0
        var skipped = 0
        while index < needleLength {
            guard haystack < length else { return 0 }
            if verse[haystack] == Self.space {
                skipped += 1
                guard skipped <= maximumSkippedSpaces else { return 0 }
                haystack += 1
                continue
            }
            guard verse[haystack] == needle[index] else { return 0 }
            haystack += 1
            index += 1
        }
        return haystack - start
    }

    private static let space = UInt8(ascii: " ")

    /// 본문 대신 **편집 안내**가 든 절인가 — `(없음)` 13건과 `(N절에 포함되어 있음)` 21건, 합 34건.
    ///
    /// 주소 34개를 코드에 박지 않고 **문자열 모양으로 가려낸다.** 목록
    /// (`docs/design-reviews/bible-curation-blocklist.md`)은 *"`bible.tdb`를 교체하면 다시 뽑아야
    /// 한다"* 고 스스로 적고 있다 — 주소를 박아 두면 본문을 갈았을 때 **조용히 어긋난다.**
    /// 모양으로 보면 데이터를 따라간다.
    ///
    /// 여는 괄호로 시작하는 절은 31,102절 중 67절뿐이고(나머지 33절은 진짜 본문의 삽입구다)
    /// 그중에서도 **이 검사는 매치된 절에서만** 돈다.
    private static func isEditorialNotice(_ verse: UnsafePointer<UInt8>, _ length: Int) -> Bool {
        guard length > 0,
              verse[0] == UInt8(ascii: "("),
              verse[length - 1] == UInt8(ascii: ")")
        else { return false }
        let text = String(decoding: UnsafeBufferPointer(start: verse, count: length), as: UTF8.self)
        return text == "(없음)" || text.hasSuffix("절에 포함되어 있음)")
    }

    private static func loadUInt16(_ base: UnsafePointer<UInt8>, _ offset: Int) -> UInt16 {
        UInt16(littleEndian: UnsafeRawPointer(base + offset).loadUnaligned(as: UInt16.self))
    }

    private static func loadUInt32(_ base: UnsafePointer<UInt8>, _ offset: Int) -> UInt32 {
        UInt32(littleEndian: UnsafeRawPointer(base + offset).loadUnaligned(as: UInt32.self))
    }
}
