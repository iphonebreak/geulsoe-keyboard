import Foundation

/// 단어 하나에 걸린 이모지들 — CLDR 한국어 이모지 주석의 역색인 한 항목
/// (PDR `docs/design-reviews/emoji-word-suggestion.md` 2절, 반입 기록 `emoji-data-import.md`).
public struct EmojiAnnotation: Equatable, Sendable {
    /// CLDR 파일 순서 그대로. **이 순서는 대표성과 무관하다** — 코드포인트 순이라 「자동차」의 첫 값은
    /// 🚕(택시)다(PDR 2-3절). 첫 값을 대표로 쓰지 않는다 — 대표는 `RepresentativeEmojiResolver`가 고른다.
    public let emojis: [String]
    /// tts(짧은 이름)가 단어와 정확히 같은 이모지 — 「자동차」→🚗. 없으면 nil. 있으면 `emojis` 안에 있다.
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

/// 사람이 고른 대표 이모지 — 손질 목록(확정 결정 Q7·Q9). 번들 `EmojiCuration.json`.
///
/// ```json
/// { "override": { "맥주": "🍺", "다리": "" }, "fallback": { "사과": "🍎" } }
/// ```
///
/// - `override` — 이름(tts) 일치보다 **먼저** 본다. 값이 빈 문자열이면 그 단어엔 이모지를 띄우지 않는다
///   (이름 일치가 엉뚱한 동음이의어를 막는 자리).
/// - `fallback` — 「검토한 대체」. 이름 일치가 **없을 때만** 쓴다. CLDR이 나중에 이름 일치를 새로 주면
///   그쪽에 자리를 내준다는 점이 `override`와 다르다.
///
/// 값 검사(한글 2~12자 키, iOS 17 카탈로그 안의 단일 이모지)는 `tools/convert_emoji.py`가 매 실행 한다.
public struct EmojiCuration: Codable, Equatable, Sendable {
    public var overrides: [String: String]
    public var fallbacks: [String: String]

    public static let empty = EmojiCuration()

    public init(overrides: [String: String] = [:], fallbacks: [String: String] = [:]) {
        self.overrides = overrides
        self.fallbacks = fallbacks
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
