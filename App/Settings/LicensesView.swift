import SwiftUI

/// 오픈소스·데이터 출처 표기.
///
/// 추천단어 사전은 CC-BY-SA-4.0 데이터의 파생물이라 이 표기가 **라이선스 의무**다 —
/// 문구를 줄이거나 화면을 없애려면 먼저 `docs/design-reviews/word-suggestions.md`를 확인할 것.
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
