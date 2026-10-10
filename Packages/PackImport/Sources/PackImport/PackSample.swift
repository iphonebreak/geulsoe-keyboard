import Foundation

/// 고정 샘플 — 3-A 「처음이라면」의 번호형·문구형 샘플과 3-C 공유 시트(PDR `docs/design-reviews/external-snippet-packs.md` 6-6·13-1(R5), AC-29).
///
/// 번들 리소스 `Samples/`는 기획자 원본 `docs/design/external-snippet-packs/sample-*.original.csv`와 그 원본에서 만든 xlsx
/// (`tools/generate_sample_xlsx.py`, 1-e ④)를 **바이트 그대로** 복사한 것이다(6-6 ③ — 번들 이름만 `sample-*.csv`·`sample-*.xlsx`,
/// 해시는 제작 기록 `sample-build-record.md`와 같다: `PackSampleTests`). 내용은 가짜 문구다(U6). 이 모듈은 앱 전용이라 샘플도 키보드 바이너리에 실리지 않는다.
/// **판이 내보내는 형식만 꺼낸다**(`bundledURL`) — CSV 전용판은 xlsx 샘플이 번들에 있어도 알약·공유 사본 어디에도 닿지 않는다(AC-35, 1-e ④ 판별 규칙).
public enum PackSample {

    public enum Kind: CaseIterable, Sendable {
        case numbered
        case phrases
    }

    public enum Format: Sendable {
        case csv
        case xlsx

        public var fileExtension: String {
            switch self {
            case .csv: "csv"
            case .xlsx: "xlsx"
            }
        }
    }

    public struct File: Hashable, Sendable {
        public let kind: Kind
        public let format: Format

        public init(kind: Kind, format: Format) {
            self.kind = kind
            self.format = format
        }

        /// 번들 속 이름(영어) — `sample-numbered.csv`
        var resourceName: String {
            switch kind {
            case .numbered: "sample-numbered"
            case .phrases: "sample-phrases"
            }
        }

        /// 번들 파일 — 지금 판이 내보내지 않는 형식(CSV 전용판의 xlsx)이거나 이 빌드에 없으면 nil
        public var bundledURL: URL? {
            guard PackCopySet.current.lines.sampleFormats.contains(format) else { return nil }
            return Bundle.module.url(forResource: resourceName, withExtension: format.fileExtension, subdirectory: PackSample.directoryName)
        }

        /// 사용자에게 보이는 이름 — 「번호형 샘플.csv」(시안 3-C). 「파일에 저장」하면 이 이름으로 남는다
        public var displayName: String { "\(PackImportCopy.sampleTitle(kind)).\(format.fileExtension)" }
    }

    static let directoryName = "Samples"

    /// 이 빌드의 샘플 폴더(번들 리소스) — 시험이 그 안의 파일을 전부 검사한다(AC-29·AC-35)
    public static var bundledDirectory: URL? { Bundle.module.url(forResource: directoryName, withExtension: nil) }

    /// 지금 판이 3-A에 보이는 그 종류의 샘플 — 알약 순서(`PackCopySet.Lines.sampleFormats`)
    public static func files(_ kind: Kind) -> [File] {
        PackCopySet.current.lines.sampleFormats.map { File(kind: kind, format: $0) }
    }

    /// 공유 시트에 넘길 사본 — 번들 파일을 `directory`에 **보이는 이름으로, 바이트 그대로** 쓴다. 번들 이름(영어)으로 넘기면 받는 쪽에
    /// 「sample-numbered.csv」로 남기 때문이다. 고정 샘플이라 사용자 입력은 담기지 않는다. 같은 이름이 있으면 덮어쓴다
    public static func exportCopy(_ file: File, into directory: URL) throws -> URL {
        guard let source = file.bundledURL else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(file.displayName, isDirectory: false)
        try Data(contentsOf: source).write(to: destination, options: .atomic)
        return destination
    }

    /// 공유 사본을 두는 곳 — 앱 임시 폴더(시스템이 비운다)
    public static var shareDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("PackSamples", isDirectory: true)
    }

    /// `exportCopy`를 전역 큐에서 — 화면(메인)은 기다리는 동안 멈추지 않는다. 만들지 못한 파일(번들에 없음·쓰기 실패)은 빠진다(그 알약이 안 보인다)
    public static func prepareForSharing(_ files: [File], into directory: URL = shareDirectory,
                                         queue: DispatchQueue = .global(qos: .userInitiated)) async -> [File: URL] {
        await withCheckedContinuation { continuation in
            queue.async {
                var prepared: [File: URL] = [:]
                for file in files {
                    prepared[file] = try? exportCopy(file, into: directory)
                }
                continuation.resume(returning: prepared)
            }
        }
    }
}
