import CryptoKit
import Foundation
import Testing
import TadakDomain
@testable import PackImport

// 외부 채움글 1-c 6단계 ④⑤ — 고정 샘플 CSV 2종(번호형·문구형)을 번들에 넣고 3-C 공유 시트로 내보낸다
// (PDR `external-snippet-packs.md` 6-6 ③ 「번들 CSV는 `*.original.csv`」·13-1(R5) · AC-29, 시안 3-A 「처음이라면」·3-C).
// 번들 파일은 기획자 원본을 **바이트 그대로** 복사한 것이다 — 해시는 제작 기록 `docs/design/external-snippet-packs/sample-build-record.md`와 같아야 한다.
// `/docs/`는 저장소에 올리지 않는다(.gitignore) — 그래서 기록의 해시를 아래 표에 옮겨 두고 **늘** 대조하며, 문서가 있는 기기에서는 표가 기록과 같은지도 본다.

/// 제작 기록 표(2026-10-04)의 SHA-256 — 샘플을 다시 만들면 기록과 이 표를 함께 고친다(기록의 「다시 만들 때」)
private let recordedSHA256: [PackSample.Kind: String] = [
    .numbered: "40720ce4dc8c0f039bf7b4ac296e321b9658f70738c3241beb946badfe48dcf8",
    .phrases: "16d2e659d40876dac0dfa4f7ace5653367d66c59ca6d9825919f8db1d62e4fbe"
]

/// 기획자 원본 이름 — 시험 픽스처(`Fixtures/`, 4단계에 원본을 그대로 복사)와 문서 폴더에 같은 이름으로 있다
private func originalName(_ kind: PackSample.Kind) -> String { kind == .numbered ? "sample-numbered.original" : "sample-phrases.original" }

/// 저장소의 샘플 원본 폴더 — 이 시험 파일에서 거슬러 올라간다(`Packages/PackImport/Tests/PackImportTests/`). 로컬 전용이라 없을 수 있다
private let sampleDocsDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()   // PackImportTests · Tests · PackImport
    .deletingLastPathComponent().deletingLastPathComponent()                               // Packages · 저장소
    .appendingPathComponent("docs/design/external-snippet-packs")

private let hasSampleDocs = FileManager.default.fileExists(atPath: sampleDocsDirectory.appendingPathComponent("sample-build-record.md").path)

private func csvFile(_ kind: PackSample.Kind) -> PackSample.File { PackSample.File(kind: kind, format: .csv) }

private func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

/// 제작 기록 표에서 그 원본 파일 줄의 SHA-256
private func recordedHash(_ original: String) throws -> String {
    let record = try String(contentsOf: sampleDocsDirectory.appendingPathComponent("sample-build-record.md"), encoding: .utf8)
    let row = try #require(record.split(separator: "\n").first { $0.contains("`\(original)`") })
    let hash = try #require(row.range(of: "[0-9a-f]{64}", options: .regularExpression))
    return String(row[hash])
}

/// PDR 13-1(R5)·13-2(R6) — 스프레드시트가 수식·명령으로 읽을 수 있는 시작 글자: `= + - @`(전각 포함) · 탭 · CR · LF
private let dangerousLeadingCharacters: Set<Character> = ["=", "+", "-", "@", "＝", "＋", "－", "＠", "\t", "\r", "\n", "\r\n"]

private func startsDangerously(_ cell: String) -> Bool { cell.first.map(dangerousLeadingCharacters.contains) ?? false }

@Suite("외부 채움글 1-c 6단계 ④ — 고정 샘플 CSV (AC-29 · 제작 기록 해시)")
struct PackSampleBundleTests {

    @Test("위험 시작 글자 판정(AC-29) — `= + - @`·전각·탭·CR·LF로 시작하면 걸리고, 가운데에 있으면 괜찮다", arguments: [
        ("=1+2", true), ("+82", true), ("-목록", true), ("@이름", true), ("＝합계", true), ("＋", true), ("－", true), ("＠", true),
        ("\t탭", true), ("\r", true), ("\n줄", true), ("\r\n줄", true),
        ("일석이조 — 한 가지 일로", false), ("1", false), ("#이름", false), ("", false), ("회의 시작 = 인사", false)
    ])
    func dangerousStart(_ cell: String, dangerous: Bool) {
        #expect(startsDangerously(cell) == dangerous)
    }

    @Test("★ AC-29 — 번들 CSV의 모든 셀(정보 줄·머리글 포함)이 위험 시작 글자로 시작하지 않는다", arguments: PackSample.Kind.allCases)
    func noDangerousCells(_ kind: PackSample.Kind) throws {
        let url = try #require(csvFile(kind).bundledURL)
        let text = try PackTextDecoder.decode(Data(contentsOf: url)).text
        let records = try CSVRecordParser.parse(text, delimiter: .comma).records
        // 검사가 실제 셀을 돈다 — 정보 줄 + 머리글 + 데이터(번호형 3 + 1 + 20 · 문구형 2 + 1 + 15)
        #expect(records.count == (kind == .numbered ? 24 : 18))
        for cell in records.flatMap(\.cells) { #expect(!startsDangerously(cell), "\(kind): \(cell.debugDescription)") }
    }

    @Test("★ 번들 파일 SHA-256 == 제작 기록 — 그리고 기획자 원본(시험 픽스처)과 바이트가 같다(6-6 ③)", arguments: PackSample.Kind.allCases)
    func hashMatchesRecord(_ kind: PackSample.Kind) throws {
        let bundled = try Data(contentsOf: try #require(csvFile(kind).bundledURL))
        #expect(sha256(bundled) == recordedSHA256[kind])
        let fixture = try #require(Bundle.module.url(forResource: originalName(kind), withExtension: "csv", subdirectory: "Fixtures"))
        #expect(bundled == (try Data(contentsOf: fixture)))
        #expect(bundled.starts(with: [0xEF, 0xBB, 0xBF]))   // UTF-8 BOM — 엑셀이 글자를 바로 읽는다(6-6 ③)
    }

    @Test("제작 기록 문서와 대조 — 위 해시 표가 기록 표와 같고, 번들 파일이 문서 폴더의 원본과 같다(문서가 있는 기기에서만)",
          .enabled(if: hasSampleDocs), arguments: PackSample.Kind.allCases)
    func recordDocumentAgrees(_ kind: PackSample.Kind) throws {
        #expect(recordedSHA256[kind] == (try recordedHash("\(originalName(kind)).csv")))
        let bundled = try Data(contentsOf: try #require(csvFile(kind).bundledURL))
        #expect(bundled == (try Data(contentsOf: sampleDocsDirectory.appendingPathComponent("\(originalName(kind)).csv"))))
    }

    @Test("번들 샘플은 그대로 팩이 된다 — 건너뜀 0 · 파일 정보 줄로 폼이 채워지고 「파일에 적힌 표기」만 고르면 가져오기가 켜진다(AC-27 준비)",
          arguments: PackSample.Kind.allCases)
    func importsCleanly(_ kind: PackSample.Kind) throws {
        let data = try Data(contentsOf: try #require(csvFile(kind).bundledURL))
        guard case .draft(let draft) = try PackImporter.read(data) else {
            Issue.record("구분자를 물었다")
            return
        }
        #expect(draft.skipped.isEmpty && !draft.needsEncodingConfirmation)
        #expect(draft.mode == (kind == .numbered ? .numbered : .phrases))
        #expect(kind == .numbered ? draft.items.count == 20 : draft.entries.count == 15)
        var form = PackImportForm(draft: draft)
        #expect(!form.isComplete)                    // 권리는 미리 고르지 않는다(시안 리뷰 수정 1)
        form.licenseChoice = .fromFile
        #expect(form.isComplete)
        let pack = try PackCompiler.compile(draft, form: form.packForm)
        #expect(pack.name == (kind == .numbered ? "사자성어 예시 팩" : "업무 상용구 예시"))
        #expect(pack.license == "글쇠 고정 샘플 — 자체 작성 문구(가짜 내용)")
    }
}

@Suite("외부 채움글 1-c 6단계 ⑤ — 샘플 받기(3-C 공유 시트)")
struct PackSampleShareTests {

    @Test("★ 보이는 파일 이름은 시안 3-C 그대로 — 「번호형 샘플.csv」「문구형 샘플.csv」(번들 속 이름은 영어)")
    func displayNames() {
        #expect(csvFile(.numbered).displayName == "번호형 샘플.csv")
        #expect(csvFile(.phrases).displayName == "문구형 샘플.csv")
        #expect(csvFile(.numbered).bundledURL?.lastPathComponent == "sample-numbered.csv")
        #expect(PackImportCopy.sampleTitle(.numbered) == "번호형 샘플" && PackImportCopy.sampleTitle(.phrases) == "문구형 샘플")
        #expect(PackImportCopy.sampleDetail(.numbered) == "사자성어·상용 영어처럼 번호로 고르는 자료")
        #expect(PackImportCopy.sampleDetail(.phrases) == "단축어를 치면 문구가 떠요")
        #expect(PackImportCopy.samplesFooter == "샘플은 가짜 내용이에요. 열어서 내용만 바꿔 저장하면 팩이 돼요.")
        #expect(PackImportCopy.sampleFormatLabel(.csv) == "CSV" && PackImportCopy.sampleFormatLabel(.xlsx) == "엑셀")
        #expect(PackImportCopy.sampleShareLabel(csvFile(.numbered)) == "번호형 샘플 CSV 받기")
    }

    @Test("★ 공유 사본 — 보이는 이름으로 바이트 그대로 복사하고, 다시 만들어도(덮어써도) 같다")
    func exportCopy() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PackSampleShareTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        for kind in PackSample.Kind.allCases {
            let file = csvFile(kind)
            let bundled = try Data(contentsOf: try #require(file.bundledURL))
            let first = try PackSample.exportCopy(file, into: directory)
            #expect(first.lastPathComponent == file.displayName)
            #expect(try Data(contentsOf: first) == bundled)
            let again = try PackSample.exportCopy(file, into: directory)
            #expect(again == first)
            #expect(try Data(contentsOf: again) == bundled)
        }
    }

    @Test("공유 준비(메인 밖) — 번들에 있는 파일만 준비된다. xlsx 샘플은 아직 번들에 없다(1-e)")
    func prepareForSharing() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PackSampleShareTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let xlsx = PackSample.File(kind: .numbered, format: .xlsx)
        #expect(xlsx.bundledURL == nil)
        let prepared = await PackSample.prepareForSharing([csvFile(.numbered), csvFile(.phrases), xlsx], into: directory)
        #expect(Set(prepared.keys) == [csvFile(.numbered), csvFile(.phrases)])
        #expect(prepared[csvFile(.phrases)]?.lastPathComponent == "문구형 샘플.csv")
    }
}
