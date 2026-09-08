import SwiftUI
import TadakDomain

/// 자판 탭 — 입력 테스트, 자판(배열·높이·숫자 줄…), 영어(자동 대문자), 피드백(진동·소리).
struct KeyboardTab: View {

    @Binding var settings: KeyboardSettings

    @State private var testText = ""
    @FocusState private var isTestFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                testSection
                layoutSection
                englishSection
                feedbackSection
            }
            .navigationTitle("자판")
        }
    }

    private var testSection: some View {
        Section {
            TextField("여기에 입력해 키보드를 확인하세요", text: $testText, axis: .vertical)
                .lineLimit(3...6)
                .focused($isTestFieldFocused)
            if !testText.isEmpty {
                Button("지우기") { testText = "" }
                    .foregroundStyle(.red)
            }
        } header: {
            Text("입력 테스트")
        } footer: {
            Text("키보드가 뜨면 지구본을 눌러 글쇠로 전환하세요.")
        }
    }

    private var layoutSection: some View {
        Section {
            Picker("한글 자판", selection: $settings.activeHangulLayout) {
                ForEach(HangulLayout.allCases, id: \.self) { layout in
                    Text(layout.displayName).tag(layout)
                }
            }

            if settings.activeHangulLayout == .cheonjiin {
                timeoutSlider(
                    "같은 키 연타 인정 시간",
                    value: $settings.cheonjiinTimeout,
                    range: 0.3...1.5
                )
            }
            if settings.activeHangulLayout == .danmoeum {
                timeoutSlider(
                    "연타 승격 인정 시간",
                    value: $settings.danmoeumTimeout,
                    range: 0.2...0.8
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("키보드 높이")
                    Spacer()
                    Text("\(Int((settings.clampedHeightScale * 100).rounded()))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $settings.keyboardHeightScale,
                       in: KeyboardSettings.heightScaleRange, step: 0.05)
            }
            .padding(.vertical, 2)
            Toggle("키 미리보기", isOn: $settings.showsKeyPreview)
            Toggle("스페이스 두 번으로 마침표", isOn: $settings.doubleSpacePeriod)
            Toggle("숫자 줄 표시", isOn: $settings.numberRowEnabled)
            Toggle("길게 눌러 기호 입력", isOn: $settings.longPressSymbolsEnabled)
        } header: {
            Text("자판")
        } footer: {
            Text("숫자 줄과 길게 눌러 기호 입력은 두벌식·단모음·영어 자판에만 적용돼요.")
        }
    }

    /// 자동 대문자 — 영어 자판 전용. 입력란 규칙(`autocapitalizationType`)과 AND로 합쳐진다
    /// (PDR auto-capitalization).
    private var englishSection: some View {
        Section("영어") {
            Toggle("자동 대문자", isOn: $settings.autoCapitalization)
        }
    }

    private var feedbackSection: some View {
        Section {
            Toggle("입력 진동", isOn: $settings.hapticEnabled)
            if settings.hapticEnabled {
                levelSlider("진동 세기", value: $settings.hapticIntensity,
                            range: KeyboardSettings.hapticIntensityRange)
            }
            Toggle("입력 소리", isOn: $settings.keySoundEnabled)
            if settings.keySoundEnabled {
                levelSlider("소리 크기", value: $settings.keySoundVolume,
                            range: KeyboardSettings.keySoundVolumeRange)
            }
        } header: {
            Text("피드백")
        } footer: {
            Text("진동은 전체 접근을 허용해야 동작해요.")
        }
    }

    /// 세기·크기 슬라이더 — 10% 단위, 양끝에 약/강 라벨
    private func levelSlider(
        _ title: String, value: Binding<Double>, range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int((value.wrappedValue * 100).rounded()))%")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: 0.1) {
                Text(title)
            } minimumValueLabel: {
                Text("약").font(.caption).foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text("강").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func timeoutSlider(
        _ title: String, value: Binding<TimeInterval>, range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.1f초", value.wrappedValue))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: 0.1)
        }
        .padding(.vertical, 2)
    }
}
