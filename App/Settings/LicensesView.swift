import SwiftUI

/// 오픈소스·데이터 출처 표기.
///
/// 추천단어 사전은 CC-BY-SA-4.0 데이터의 파생물이라 이 표기가 **라이선스 의무**다 —
/// 문구를 줄이거나 화면을 없애려면 먼저 `docs/design-reviews/word-suggestions.md`를 확인할 것.
/// 이모지 추천 데이터(Unicode CLDR)도 Unicode License v3가 **고지 전문**을 요구한다 — 「라이선스 전문 보기」를
/// 지우지 말 것(근거 `docs/design-reviews/emoji-data-import.md` 3절, 데이터 옆 고지 `LICENSE-emoji.md`).
struct LicensesView: View {

    var body: some View {
        List {
            Section("추천단어 사전") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("FrequencyWords (ko_50k)")
                        .font(.headline)
                    Text("""
                    Hermit Dave의 OpenSubtitles 2018 기반 한국어 빈도 목록에서 파생했습니다. \
                    데이터는 CC-BY-SA-4.0으로 배포되며, 이 앱에 내장된 파생 사전에도 같은 \
                    라이선스가 적용됩니다.
                    """)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    Link("github.com/hermitdave/FrequencyWords",
                         destination: URL(string: "https://github.com/hermitdave/FrequencyWords")!)
                        .font(.footnote)
                    Link("CC-BY-SA-4.0 전문",
                         destination: URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!)
                        .font(.footnote)
                }
                .padding(.vertical, 2)
            }

            Section("이모지 추천 데이터") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Unicode CLDR (한국어 이모지 이름·키워드)")
                        .font(.headline)
                    Text("""
                    추천단어 줄에 함께 보여 주는 이모지는 Unicode CLDR 48.2의 한국어 이모지 이름·키워드로 \
                    만든 색인에서 고르며, 글쇠가 고른 손질 목록을 더했습니다. CLDR 데이터는 \
                    Unicode License v3(Unicode-3.0)로 제공됩니다. Copyright © 2004-2026 Unicode, Inc.
                    """)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    Link("github.com/unicode-org/cldr",
                         destination: URL(string: "https://github.com/unicode-org/cldr")!)
                        .font(.footnote)
                    Link("unicode.org/license.txt",
                         destination: URL(string: "https://www.unicode.org/license.txt")!)
                        .font(.footnote)
                }
                .padding(.vertical, 2)
                NavigationLink("라이선스 전문 보기") {
                    UnicodeLicenseView()
                }
                .font(.footnote)
            }

            Section("채움글 본문") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("성경 (개역한글판, 1961)")
                        .font(.headline)
                    Text("대한성서공회 개역한글판 — 저작권 보호 기간이 만료된 저작물입니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                VStack(alignment: .leading, spacing: 6) {
                    Text("국가 상징문")
                        .font(.headline)
                    Text("애국가(작사자 미상의 공유 저작물), 국기에 대한 맹세·대한민국헌법 전문과 전 조문(저작권법 제7조에 따라 보호받지 않는 공공 저작물, 법제처 국가법령정보센터 원문), 기미독립선언서 서두(1919, 보호 기간 만료)를 수록했습니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                VStack(alignment: .leading, spacing: 6) {
                    Text("인사·상용구")
                        .font(.headline)
                    Text("글쇠가 직접 작성한 문구입니다. 자유롭게 고쳐 쓰세요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
        .settingsFormWidth()
        .navigationTitle("오픈소스 및 출처")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Unicode License v3 고지 전문 — 조건 「(b) 고지가 관련 문서에 나타날 것」을 앱 안에서 채운다
/// (외부 링크만으로는 오프라인·링크 소멸에 약하다). 원문은 CLDR 48.2 커밋의 `LICENSE` 그대로이고
/// (SHA-256 `b49d0e9f…`), `Packages/TadakData/Sources/TadakData/Resources/LICENSE-emoji.md`에도 같은 원문이 있다.
private struct UnicodeLicenseView: View {

    /// 무엇에서 왔는지 — 버전·입력 해시·변환 규칙 (`tools/convert_emoji.py`, `emoji-data-import.md` 2·4절)
    private static let provenance = """
        Unicode CLDR — Korean emoji annotations (data derived)
        CLDR version: 48.2 (release-48-2, commit 11299982335beb974c1c63c45265184e759c0f41)
        Source: https://github.com/unicode-org/cldr
        Input files:
        common/annotations/ko.xml
        sha256=1d7007de84c0431f892b3f8c87b24835c8f8474a1711a2406592aaf24f5db72d
        common/annotationsDerived/ko.xml
        sha256=c624e7369d0b283c9f7085360157b7f5f701260b36e4e5ff3f9552ce196dbbb8
        Conversion: keywords and tts names inverted into a word → emoji index; Hangul keys of \
        2–12 syllables and single code points with default emoji presentation per Unicode 15.0 kept; \
        rewritten as a binary format for lookup.
        """

    /// 원문 그대로(줄바꿈 포함). 화면에서는 문단 안의 줄바꿈만 풀어 폭에 맞게 흐르게 한다.
    static let licenseText = """
        UNICODE LICENSE V3

        COPYRIGHT AND PERMISSION NOTICE

        Copyright © 2004-2026 Unicode, Inc.

        NOTICE TO USER: Carefully read the following legal agreement. BY
        DOWNLOADING, INSTALLING, COPYING OR OTHERWISE USING DATA FILES, AND/OR
        SOFTWARE, YOU UNEQUIVOCALLY ACCEPT, AND AGREE TO BE BOUND BY, ALL OF THE
        TERMS AND CONDITIONS OF THIS AGREEMENT. IF YOU DO NOT AGREE, DO NOT
        DOWNLOAD, INSTALL, COPY, DISTRIBUTE OR USE THE DATA FILES OR SOFTWARE.

        Permission is hereby granted, free of charge, to any person obtaining a
        copy of data files and any associated documentation (the "Data Files") or
        software and any associated documentation (the "Software") to deal in the
        Data Files or Software without restriction, including without limitation
        the rights to use, copy, modify, merge, publish, distribute, and/or sell
        copies of the Data Files or Software, and to permit persons to whom the
        Data Files or Software are furnished to do so, provided that either (a)
        this copyright and permission notice appear with all copies of the Data
        Files or Software, or (b) this copyright and permission notice appear in
        associated Documentation.

        THE DATA FILES AND SOFTWARE ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY
        KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
        MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF
        THIRD PARTY RIGHTS.

        IN NO EVENT SHALL THE COPYRIGHT HOLDER OR HOLDERS INCLUDED IN THIS NOTICE
        BE LIABLE FOR ANY CLAIM, OR ANY SPECIAL INDIRECT OR CONSEQUENTIAL DAMAGES,
        OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS,
        WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION,
        ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THE DATA
        FILES OR SOFTWARE.

        Except as contained in this notice, the name of a copyright holder shall
        not be used in advertising or otherwise to promote the sale, use or other
        dealings in these Data Files or Software without prior written
        authorization of the copyright holder.

        SPDX-License-Identifier: Unicode-3.0
        """

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(Self.provenance)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text(Self.licenseText.replacingOccurrences(
                    of: "(?<!\\n)\\n(?!\\n)", with: " ", options: .regularExpression))
                    .font(.footnote)
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .settingsFormWidth()
        .navigationTitle("Unicode License v3")
        .navigationBarTitleDisplayMode(.inline)
    }
}
