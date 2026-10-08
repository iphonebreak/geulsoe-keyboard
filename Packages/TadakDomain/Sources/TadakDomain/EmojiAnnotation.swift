import Foundation

/// 단어 하나에 걸린 이모지들 — CLDR 한국어 이모지 주석의 역색인 한 항목
/// (PDR `docs/design-reviews/emoji-word-suggestion.md` 2절, 반입 기록 `emoji-data-import.md`).
public struct EmojiAnnotation: Equatable, Sendable {
    /// CLDR 파일 순서 그대로(코드포인트 순 — 「자동차」의 첫 값은 🚕). 칩 이모지는 이 목록과 손질 목록 값을
    /// 합친 묶음에서 랜덤으로 뽑는다(확정 결정 D9 — `EmojiCuration.candidates(for:annotation:)`).
    public let emojis: [String]
    /// tts(짧은 이름)가 단어와 정확히 같은 이모지 — 「자동차」→🚗. 없으면 nil. 있으면 `emojis` 안에 있다.
    /// **D10 이후 칩 판정·뽑기에는 쓰지 않는다** — 데이터 사실로만 남긴다(손질 후보표·검증용).
    public let nameMatch: String?

    public init(emojis: [String], nameMatch: String?) {
        self.emojis = emojis
        self.nameMatch = nameMatch
    }
}

/// 단어 → 이모지 역색인 경계. 키는 **한글 음절 단어 그대로**(정확 일치)다 — 추천단어 사전처럼 자모
/// 접두로 찾지 않는다. 지금 치는 단어 자신을 1회 조회하고(확정 결정 Q1), 조사 붙은 꼴은 다루지 않는다(Q5).
public protocol EmojiAnnotationIndex: Sendable {
    /// 단어에 걸린 이모지. 키가 없으면 nil. 실패하지 않는다.
    func annotation(for word: String) -> EmojiAnnotation?
}

/// 사람이 고른 이모지 — 손질 목록(확정 결정 D8). 번들 `EmojiCuration.json`.
///
/// ```json
/// { "override": { "맥주": "🍺", "가지": "" }, "fallback": { "치킨": "🍗" } }
/// ```
///
/// **D10(2026-10-02)으로 뜻이 바뀌었다** — 형식(두 절)은 그대로다.
/// - 값은 **묶음에 더할 이모지**다. `override`든 `fallback`이든 CLDR 후보와 합쳐 랜덤 뽑기 대상이 된다(D9).
///   역색인에 없는 단어(「콜라」 등)도 손질 목록에 있으면 칩이 뜬다.
/// - `override` 값이 **빈 문자열이면 막기** — CLDR 후보가 있어도 그 단어엔 칩을 띄우지 않는다
///   (가지·가면·파리·뒤로 — 「가지 마」「가면 돼」 오발동 방지).
/// - `fallback`의 빈 문자열은 뜻이 없다(무시한다). 변환기는 이것을 거부한다 — 막으려면 `override`에 적는다.
///
/// 값 검사(한글 2~12자 키, iOS 17 = Unicode 15.0 카탈로그 안의 단일 이모지)는 `tools/convert_emoji.py`가
/// 매 실행 하고, `swift test`(TadakData)도 변환기가 내보낸 기준선 픽스처로 같은 검사를 한다.
public struct EmojiCuration: Codable, Equatable, Sendable {
    public var overrides: [String: String]
    public var fallbacks: [String: String]

    public static let empty = EmojiCuration()

    public init(overrides: [String: String] = [:], fallbacks: [String: String] = [:]) {
        self.overrides = overrides
        self.fallbacks = fallbacks
    }

    /// 칩 이모지를 뽑을 묶음 — **CLDR 후보 전부 ∪ 손질 목록 값**(D9), 중복 제거.
    ///
    /// 순서는 CLDR 파일 순서 뒤에 `override` 값, `fallback` 값 — 뽑기가 균등 랜덤이라 순서에 뜻은 없고
    /// 결정적 테스트를 위해 고정만 한다. `override`가 빈 문자열이면 빈 묶음(막기, D10).
    /// 단어 꼴 검사(완성 음절 2~12자)는 호출자 몫이다 — `annotation`은 그 단어로 조회한 결과를 넘긴다.
    public func candidates(for word: String, annotation: EmojiAnnotation?) -> [String] {
        let override = overrides[word]
        if override == "" { return [] }
        var bundle = annotation?.emojis ?? []
        for extra in [override, fallbacks[word]] {
            if let extra, !extra.isEmpty, !bundle.contains(extra) { bundle.append(extra) }
        }
        return bundle
    }

    private enum CodingKeys: String, CodingKey {
        case overrides = "override"
        case fallbacks = "fallback"
    }

    /// 빠진 절은 빈 목록이다 — 둘 중 하나만 적어도 된다.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            overrides: try container.decodeIfPresent([String: String].self, forKey: .overrides) ?? [:],
            fallbacks: try container.decodeIfPresent([String: String].self, forKey: .fallbacks) ?? [:])
    }
}

/// 손질 목록 저장소 경계 — 번들 읽기 전용.
public protocol EmojiCurationRepository: Sendable {
    /// 실패하지 않는다 — 리소스가 없거나 깨졌으면 `.empty`.
    func curation() -> EmojiCuration
}
